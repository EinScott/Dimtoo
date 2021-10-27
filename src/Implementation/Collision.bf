using System;
using System.Diagnostics;
using Pile;
using System.Collections;

namespace Dimtoo
{
	// TODO: (generally) maybe replace all these arrays with StaticList<T> which would just be a fixedcapacity list
	// also replace these for outer loops with stuff that loads the loop body as a anon function off to a threadpool?
	// -> at least test if thats faster

	// !! if we have a contact in the direction we're currently moving in, even if we dont trigger a collision (due to rounding / floats),
	//    always report one, cause that makes more sense

	// TODO: second physics system vs this system problem: what do we do if we want to push something?
	// solution:
	// -> we just gather movement info here, we just make sure no moves are invalid
	// -> the physics system should take this info about contacts and collision, and just adjust the moves it makes us do accordingly?
	// 	- if there would be multiple pushes across one frame, but taking multiple cycles here, maybe we need some prediction based on moverect??
	//		-> maybe multiple pyhs update / move - cycles per update?

	[Serializable]
	struct CollisionBody
	{
		public Vector2 move;
		public Collider collider;

		public this(Collider coll)
		{
			move = .Zero;
			collider = coll;
		}
	}

	enum Collider
	{
		case Rect(SizedList<ColliderRect, const 16> colliders);
		case Grid(Point2 offset, uint8 cellX, uint8 cellY, bool[32*32] collide, LayerMask layer);

		public Rect this[int index] =>
		{
			Rect res = default;
			switch (this)
			{
			case .Rect(let colliders):
				Debug.Assert(index < colliders.Count);
				res = colliders[index].rect;
			case .Grid(let offset,let cellX,let cellY,?,?):
				let x = index % 32;
				let y = index - x;
				res = .(offset + .(x * cellX, y * cellY), .(cellX, cellY));
			}
			res
		};

		[Inline]
		public int GetGridIndex(int x, int y)
		{
			Debug.Assert(this case .Grid);
			return y * 32 + x;
		}
	}

	[Serializable]
	struct LayerMask
	{
		public this(uint64 mask = 0x1)
		{
			val = mask;
		}

		uint64 val;

		public bool this[int layer]
		{
			[Inline]
			get => (val & (uint64)(1 << layer)) > 0;
			set mut => val |= (uint64)(1 << layer);
		}

		[Inline]
		public bool Overlaps(LayerMask other) => (val & other.val) > 0;

		[Inline]
		public static implicit operator Self(uint64 i)
		{
			LayerMask m = default;
			m.val = i;
			return m;
		}
	}

	[Serializable]
	struct ColliderRect
	{
		public this(Rect rect, Edge solid = .All, LayerMask layer = 0x1)
		{
			this.rect = rect;
			this.solid = solid; // By default all edges solid
			this.layer = layer; // By default on layer 0
		}

		public Rect rect;
		public Edge solid;
		public LayerMask layer;
	}

	// Feedback of a body's own movement collision "it collides into something else"
	[Serializable]
	struct CollisionMoveFeedback
	{
		public CollisionInfo moveCollision;
		public CollisionInfo slideCollision;

		[Inline]
		public bool Occured() => moveCollision.Occured() || slideCollision.Occured();

		[Inline]
		public Edge GetHitEdges() => moveCollision.myHitEdge | slideCollision.myHitEdge;
	}

	// Feedback of a body's received collision "something else collides into it"
	[Serializable]
	struct CollisionReceiveFeedback
	{
		public SizedList<CollisionInfo, const 16> collisions;

		[Inline]
		public bool Occured() => collisions.Count > 0;

		[Inline]
		public Edge GetHitEdges()
		{
			Edge res = .None;
			for (let i < collisions.Count)
				res |= collisions[i].myHitEdge;
			return res;
		}
	}

	[Serializable]
	struct CollisionInfo
	{
		public Entity other;
		public bool iWasMoving, otherWasMoving;
		public Vector2 myDir, otherDir;
		public Edge myHitEdge;
		public int myColliderIndex, otherColliderIndex;

		[Inline]
		public bool Occured() => myDir != .Zero || otherDir != .Zero; // To collide, someone has to move.
	}

	class CollisionSystem : ComponentSystem, IRendererSystem
	{
		public bool debugRenderCollisions;

		static Type[?] wantsComponents = .(typeof(Transform), typeof(CollisionBody));
		this
		{
			signatureTypes = wantsComponents;
		}

		public int GetRenderLayer()
		{
			return 999; // debug on top
		}

		public void Render(Batch2D batch)
		{
			if (!debugRenderCollisions)
				return;

			for (let e in entities)
			{
				let tra = componentManager.GetComponent<Transform>(e);
				let cob = componentManager.GetComponent<CollisionBody>(e);

				if (cob.move != .Zero)
					batch.Line(tra.position, tra.position + cob.move, 1, .Magenta);

				batch.HollowRect(MakePathRect(PrepareResolveSet(tra, cob, ?)), 1, .Gray);

				switch (cob.collider)
				{
				case .Grid(let offset,let cellX,let cellY,let collide, let layer):
					let origin = tra.position.Round() + offset;
					Point2 size = .(cellX, cellY);
					for (let y < 32)
						for (let x < 32)
							if (collide[y*32+x])
								batch.HollowRect(.((origin + .(x*cellX,y*cellY)), size), 1, .Red);
				case .Rect(let rects):
					for (let coll in rects)
						batch.HollowRect(.(tra.position.Round() + coll.rect.Position, coll.rect.Size), 1, .Red);
				}
			}
		}

		// @report: neither renaming tuple members or these tyaliases works properly
		// also look why rebuilding still fails on comptime & data cycles sometimes happen (look at newest fusion issue, might by the same??)
		typealias ResolveSet = (Collider coll, Point2 move, Point2 pos);

		static ResolveSet PrepareResolveSet(Transform* tra, CollisionBody* body, out Vector2 newPos)
		{
			// We move in whole pixels only, so prepare for that here!
			ResolveSet a;
			a.coll = body.collider;
			a.pos = tra.position.Round();
			a.move = body.move.Round();

			var posRemainder = (tra.position - a.pos) + (body.move - a.move);
			if (Math.Round(Math.Abs(posRemainder.X)) >= 1 || Math.Round(Math.Abs(posRemainder.Y)) >= 1)
			{
				let rounded = posRemainder.Round();
				a.move += rounded;
				posRemainder -= rounded;
			}

			// Update position remainder
			newPos = a.pos + posRemainder;

			// The position of the entity doesnt change by this, the float remainder would just move the entity in this case
			// and thus we move that onto the movement amount.
			Debug.Assert(newPos.Round() == tra.position.Round());

			return a;
		}

		[PerfTrack,Optimize]
		public void Resolve()
		{
			for (let e in entities)
				if (componentManager.GetComponentOptional<CollisionReceiveFeedback>(e, let feedback))
					feedback.collisions.Clear();

			for (let e in entities)
			{
				let aCob = componentManager.GetComponent<CollisionBody>(e);
				let aTra = componentManager.GetComponent<Transform>(e);

				// Make the resolve set for a, also manage a's remainder position when deciding integer position and movement
				var a = PrepareResolveSet(aTra, aCob, out aTra.position); // Put this into our transform to process sub-pixel movements
				aCob.move = .Zero;

				if (a.move == .Zero)
					continue; // a must move!

				// Move info
				Point2 currMove = a.move;
				CheckMove(e, ref a, let moveInfo);

				Point2 slideMove = ?;
				bool doSlide = true;
				switch (moveInfo.myHitEdge)
				{
				case .Left, .Right:
					slideMove.X = 0;
					slideMove.Y = currMove.Y;
				case .Top, .Bottom:
					slideMove.X = currMove.X;
					slideMove.Y = 0;
				case .None:
					doSlide = false;
				default:
					Debug.FatalError();
				}

				CollisionInfo slideInfo;
				if (doSlide)
				{
					currMove = a.move; // Save this here for later

					// Set up for slide simulate, pseudo-move to already confirmed position
					a.pos += a.move;
					a.move = slideMove;

					CheckMove(e, ref a, out slideInfo);

					a.move += currMove; // Add back onto confirmed slide move to get the full movement
				}
				else slideInfo = .();

				if (componentManager.GetComponentOptional<CollisionMoveFeedback>(e, let collFeedback))
				{
					collFeedback.moveCollision = moveInfo;
					collFeedback.slideCollision = slideInfo;
				}

				// Actually move
				aTra.position += a.move;
			}
		}
		
		[Optimize]
		void CheckMove(Entity eMove, ref ResolveSet a, out CollisionInfo aInfo)
		{
			var moverPathRect = MakePathRect(a);

			float hitPercent = 1;
			aInfo = .();

			Entity eHit = 0;
			CollisionInfo bInfo = .();

			for (let eOther in entities)
			{
				if (eMove == eOther)
					continue; // b is not a!

				let bCob = componentManager.GetComponent<CollisionBody>(eOther);
				let bTra = componentManager.GetComponent<Transform>(eOther);

				let b = PrepareResolveSet(bTra, bCob, ?);
				let checkPathRect = MakePathRect(b);

				// If they overlap the moveRect
				if (moverPathRect.Overlaps(checkPathRect))
				{
					bool otherMoving = false;
					if (b.move != .Zero)
					{
						otherMoving = true;

						// TODO: how do we handle moving b that moves?
						// we will probably (since the movements here are "instant" / all made in the same amount of time) just move both to the same percentage until it works? -- some fancy math?
						// -> DEF a test to figure out the direction of the movers, and if their directons dont interfere / are opposite, just ignore
						// 	-> also need to handle contacts differently, since after their own resolve, they might be anywhere inside their moveRect

						// do we just need to get the overlap rect of their move rects, then look at if they actually both move towards it (or their end position still overlap).
						// if they move in the same direction, we need to call a recursive function (prob move content of outer loop in one)
						//	to move that first!, then us to not overlap and make sure their move is valid (they actaully move where the plan to)
						// when we know they will confront on the other hand, .. what exactly then?

						// i guess we could approximate by just letting the one that moves further take all overlapping space? in most cases its probably just one pixel anyway
						// YEAH thats fair, i mean we also fail to do sliding proberly after the distance is too high

						// -> comment both of those limitations in movement at both places in the code, delete this after work is done.
					}

					bool moveChanged = false;
					switch ((a.coll, b.coll))
					{
					case (.Rect(let aRects), .Rect(let bRects)):
						for (let aColl in aRects)
						{
							let aRect = Rect(a.pos + aColl.rect.Position, aColl.rect.Size);
							for (let bColl in bRects)
								if (aColl.layer.Overlaps(bColl.layer))
								{
#if DEBUG
									bool dbgColliderEntered = false;
#endif
									let bRect = Rect(b.pos + bColl.rect.Position, bColl.rect.Size);
	
									CHECK:do if (!aRect.Overlaps(bRect) // Do not get stuck when already inside
										&& CheckRects(aRect, bRect, a.move, let newHitPercent, let newHitEdge)
										&& newHitPercent < hitPercent)
									{
										if ((aColl.solid & newHitEdge) == 0 || (bColl.solid & newHitEdge.Inverse) == 0)
										{
#if DEBUG
											dbgColliderEntered = true; // We entered the collider through a non-solid edge
#endif
											break CHECK;
										}
	
										aInfo = .()
											{
												iWasMoving = true,
												myHitEdge = newHitEdge,
												myColliderIndex = @aColl.Index,
												myDir = ((Vector2)a.move).Normalize(),
	
												other = eOther,
												otherWasMoving = otherMoving,
												otherColliderIndex = @bColl.Index,
												otherDir = ((Vector2)b.move).Normalize()
											};
	
										if (componentManager.GetComponentOptional<CollisionReceiveFeedback>(eOther, ?))
										{
											eHit = eOther;
											bInfo = .()
												{
													iWasMoving = otherMoving,
													myHitEdge = newHitEdge.Inverse,
													myColliderIndex = @bColl.Index,
													myDir = ((Vector2)b.move).Normalize(),
	
													other = eMove,
													otherWasMoving = true,
													otherColliderIndex = @aColl.Index,
													otherDir = ((Vector2)a.move).Normalize()
												};
										}
										
										hitPercent = newHitPercent;
										a.move = ((Vector2)a.move * hitPercent).Round();
	
										moveChanged = true;
									}
#if DEBUG
									else dbgColliderEntered = true; // We were already inside that collider before moving
	
									Debug.Assert(dbgColliderEntered || !Rect(a.pos + a.move + aColl.rect.Position, aColl.rect.Size).Overlaps(bRect), "Mover entered collider illegally.");
#endif
								}
						}
					case (.Rect(let rects), .Grid(let offset,let cellX,let cellY,let collide, let layer)):
						for (let aColl in rects)
						{
							if (aColl.layer.Overlaps(layer))
							{
								let aRect = Rect(a.pos + aColl.rect.Position, aColl.rect.Size);
								for (let y < 32)
									for (let x < 32)
										if (collide[y * 32 + x])
										{
#if DEBUG
											bool dbgColliderEntered = false;
#endif
											let bRect = Rect(b.pos + offset + .(x * cellX, y * cellY), .(cellX, cellY));

											CHECK:do if (!aRect.Overlaps(bRect) // Do not get stuck when already inside
												&& CheckRects(aRect, bRect, a.move, let newHitPercent, let newHitEdge)
												&& newHitPercent < hitPercent)
											{
												if ((aColl.solid & newHitEdge) == 0)
												{
#if DEBUG
													dbgColliderEntered = true; // We entered the collider through a non-solid edge
#endif
													break CHECK;
												}

												aInfo = .()
													{
														iWasMoving = true,
														myHitEdge = newHitEdge,
														myColliderIndex = @aColl.Index,
														myDir = ((Vector2)a.move).Normalize(),

														other = eOther,
														otherWasMoving = otherMoving,
														otherColliderIndex = y * 32 + x,
														otherDir = ((Vector2)b.move).Normalize()
													};

												if (componentManager.GetComponentOptional<CollisionReceiveFeedback>(eOther, ?))
												{
													eHit = eOther;
													bInfo = .()
														{
															iWasMoving = otherMoving,
															myHitEdge = newHitEdge.Inverse,
															myColliderIndex = y * 32 + x,
															myDir = ((Vector2)b.move).Normalize(),

															other = eMove,
															otherWasMoving = true,
															otherColliderIndex = @aColl.Index,
															otherDir = ((Vector2)a.move).Normalize()
														};
												}
												
												hitPercent = newHitPercent;
												a.move = ((Vector2)a.move * hitPercent).Round();

												moveChanged = true;
											}
#if DEBUG
											else dbgColliderEntered = true; // We were already inside that collider before moving

											Debug.Assert(dbgColliderEntered || !Rect(a.pos + a.move + aColl.rect.Position, aColl.rect.Size).Overlaps(bRect), "Mover entered collider illegally.");
#endif
										}
							}
						}
					default: Debug.FatalError("Collider movement not implemented");
					}

					if (moveChanged)
					{
						// Update pathRect based on new move
						moverPathRect = MakePathRect(a);
					}
				}
			}

			// Apply the collision received on b
			if (eHit != 0)
			{
				// Since this was set, we know this exists on the entity
				let feedback = componentManager.GetComponent<CollisionReceiveFeedback>(eHit);
				feedback.collisions.Add(bInfo);
			}
		}

		[Optimize]
		static bool CheckRects(Rect a, Rect b, Point2 movement, out float hitPercent, out Edge hitEdge)
		{
			hitPercent = 0;
			float outPercent = 1.0f;
			Vector2 overlapPercent = Vector2.Zero;
			hitEdge = .None;

			// X axis overlap

			// a moves right
			if (movement.X > 0)
			{
				if (b.Right < a.Left) return false; // a is already right of b
				if (b.Right >= a.Left) outPercent = Math.Min((a.Left - b.Right) / -(float)movement.X, outPercent); // a is inside or left of b

				if (a.Right <= b.Left) // a is left of b
				{
					overlapPercent.X = (a.Right - b.Left) / -(float)movement.X;
					hitPercent = Math.Max(overlapPercent.X, hitPercent);
					hitEdge = Edge.Right;
				}
			}
			// a moves left
			else if (movement.X < 0)
			{
				if (b.Left > a.Right) return false; // a is already left of b
				if (b.Left <= a.Right) outPercent = Math.Min((a.Right - b.Left) / -(float)movement.X, outPercent); // a is inside or right of b

				if (a.Left >= b.Right) // a is right of b
				{
					overlapPercent.X = (a.Left - b.Right) / -(float)movement.X;
					hitPercent = Math.Max(overlapPercent.X, hitPercent);
					hitEdge = Edge.Left;
				}
			}
			// a doesn't move on x
			else
			{
				if (b.Left >= a.Right) return false;
				if (b.Right <= a.Left) return false;
			}

			if (hitPercent > outPercent) return false;

			//=================================

			// Y axis overlap

			// a moves down
			if (movement.Y > 0)
			{
				if (b.Bottom < a.Top) return false; // a is already under b
				if (b.Bottom >= a.Top) outPercent = Math.Min((a.Top - b.Bottom) / -(float)movement.Y, outPercent); // a is inside or above b

				if (a.Bottom <= b.Top) // a is above b
				{
					overlapPercent.Y = (a.Bottom - b.Top) / -(float)movement.Y;
					hitPercent = Math.Max(overlapPercent.Y, hitPercent);
					hitEdge = Edge.Bottom;
				}
			}
			// a moves up
			else if (movement.Y < 0)
			{
				if (b.Top > a.Bottom) return false; // a is already above b
				if (b.Top <= a.Bottom) outPercent = Math.Min((a.Bottom - b.Top) / -(float)movement.Y, outPercent); // a is inside or under b

				if (a.Top >= b.Bottom) // a is under b
				{
					overlapPercent.Y = (a.Top - b.Bottom) / -(float)movement.Y;
					hitPercent = Math.Max(overlapPercent.Y, hitPercent);
					hitEdge = Edge.Top;
				}
			}
			// a doesn't move on y
			else
			{
				if (b.Bottom <= a.Top) return false;
				if (b.Top >= a.Bottom) return false;
			}

			if (hitPercent > outPercent) return false;

			return true;
		}

		[Optimize]
		// For non-mover entities, this just returns bounds
		static Rect MakePathRect(ResolveSet s)
		{
			let pos = s.pos;
			var origin = pos;
			var size = Point2.Zero;

			// Get bounds
			switch (s.coll)
			{
			case .Grid(let offset,let cellX,let cellY,let collide,?):
				// Get grid tile bounds
				Point2 min = .(32, 32), max = default;
				for (let y < 32)
					for (let x < 32)
						if (collide[y * 32 + x])
						{
							if (x < min.X) min.X = x;
							if (x > max.X) max.X = x;

							if (y < min.Y) min.Y = y;
							if (y > max.Y) max.Y = y;
						}

				min *= cellX;
				max *= cellY;
				min -= offset;
				max -= offset;

				max += .(cellX, cellY);

				origin += min;
				size = max - min;

				break;
			case .Rect(let colliders):
				for (let i < colliders.Count)
				{
					let boxOrig = pos + colliders[i].rect.Position;

					// Leftmost corner
					if (boxOrig.X < origin.X)
						origin.X = boxOrig.X;
					if (boxOrig.Y < origin.Y)
						origin.Y = boxOrig.Y;

					// Size
					let boxSize = colliders[i].rect.Size;
					if (boxOrig.X + boxSize.X > origin.X + size.X)
						size.X = boxSize.X;
					if (boxOrig.Y + boxSize.Y > origin.Y + size.Y)
						size.Y = boxSize.Y;
				}
				break;
			}

			// Expand by movement
			if (s.move != .Zero)
			{
				size += Point2.Abs(s.move);
				if (s.move.X < 0)
					origin.X += s.move.X;
				if (s.move.Y < 0)
					origin.Y += s.move.Y;
			}

			return Rect(origin, size);
		}
	}
}
