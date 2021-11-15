using System;
using System.Diagnostics;
using Pile;
using System.Collections;

namespace Dimtoo
{
	// Unconventional 2d collision detection & response

	// TODO: replace these for outer loops with stuff that loads the loop body as a anon function off to a threadpool?
	// -> at least test if thats faster

	// !! if we have a contact in the direction we're currently moving in, even if we dont trigger a collision (due to rounding / floats),
	//    always report one, cause that makes more sense

	// TODO: second physics system vs this system problem: what do we do if we want to push something?
	// solution:
	// -> we just gather movement info here, we just make sure no moves are invalid
	// -> the physics system should take this info about contacts and collision, and just adjust the moves it makes us do accordingly?
	// 	- if there would be multiple pushes across one frame, but taking multiple cycles here, maybe we need some prediction based on moverect??
	//		-> maybe multiple pyhs update / move - cycles per update?
	//	(or just PreCollTick and PostCollTick) or similar!

	typealias ColliderList = SizedList<ColliderRect, const 16>;

	[Serializable]
	struct CollisionBody
	{
		public Vector2 move;
		public ColliderList colliders;

		public this(ColliderList coll)
		{
			move = .Zero;
			colliders = coll;
		}

		public Rect GetCollider(int index)
		{
			Debug.Assert((uint)index < (uint)colliders.Count);
			return colliders[index].rect;
		}
	}

	[Serializable]
	enum ColliderType
	{
		Rect,
		Grid
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
		public ColliderType otherColliderType;

		[Inline]
		public bool Occured() => myDir != .Zero || otherDir != .Zero; // To collide, someone has to move.
	}

	class CollisionSystem : ComponentSystem, IRendererSystem
	{
		public bool debugRenderCollisions;

#if DEBUG
		List<Rect> dbgLastMoveCheckedRects = new List<Rect>() ~ delete _;
#endif

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

				for (let coll in cob.colliders)
					batch.HollowRect(.(tra.position.Round() + coll.rect.Position, coll.rect.Size), 1, .Red);
			}

#if DEBUG
			for (let r in dbgLastMoveCheckedRects)
				batch.HollowRect(r, 1, .Green);
#endif
		}

		typealias ResolveSet = (ColliderList coll, Point2 move, Point2 pos);

		static ResolveSet PrepareResolveSet(Transform* tra, CollisionBody* body, out Vector2 newPos)
		{
			// We move in whole pixels only, so prepare for that here!
			ResolveSet a;
			a.coll = body.colliders;
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
		public void Resolve(GridSystem gridSys)
		{
			for (let e in entities)
				if (componentManager.GetComponentOptional<CollisionReceiveFeedback>(e, let feedback))
					feedback.collisions.Clear();

#if DEBUG
			let dbgRectCount = dbgLastMoveCheckedRects.Count;
#endif

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
				CheckMove(e, ref a, var moveInfo, gridSys);

				CollisionInfo slideInfo;
				{
					let hitX = ((moveInfo.myHitEdge & .Left) != 0 || (moveInfo.myHitEdge & .Right) != 0);
					let hitY = ((moveInfo.myHitEdge & .Top) != 0 || (moveInfo.myHitEdge & .Bottom) != 0);

					switch ((hitX, hitY))
					{
					case (true, false):
						DoSlide(e, ref a, .(0, currMove.Y), out slideInfo, gridSys);
					case (false, true):
						DoSlide(e, ref a, .(currMove.X, 0), out slideInfo, gridSys);
					case (true, true): // We hit a corner!
						Point2 primCheck, secCheck;
						let xIsPrimaryMove = Math.Abs(currMove.X) > Math.Abs(currMove.Y);
						if (xIsPrimaryMove)
						{
							primCheck = .(currMove.X, 0);
							secCheck = .(0, currMove.Y);
						}
						else
						{
							primCheck = .(0, currMove.Y);
							secCheck = .(currMove.X, 0);
						}

						let equalMove = Math.Abs(currMove.X) == Math.Abs(currMove.Y);

						let establishedMove = a.move; // Result from the first move check, save for later

						// Set up for slide simulate, pseudo-move to already confirmed position
						a.pos += a.move;
						a.move = primCheck;

						CheckMove(e, ref a, out slideInfo, gridSys);

						if (a.move == .Zero || equalMove) // Check second one, if first side blocks or we move equally in both directions
						{
							// Save for later compare
							let primInfo = slideInfo;
							let primMove = a.move;

							a.move = secCheck;

							CheckMove(e, ref a, out slideInfo, gridSys);

							if (equalMove) // We move equally to both sides from the corner, and could also go to both
							{
								// NOTE: in here, primCheck is ALWAYS the Y movement!

								// This is to avoid getting stuck on corners where adjacent colliders actually form a continuous edge
								// and where we thus should not get stuck, so we have to check both options and decide here

								if (a.move != .Zero && primMove != .Zero)
									a.move = .Zero; // We perfectly hit the corner, do nothing! (and also leave both edges)
								else if (a.move == .Zero)
								{
									// We cannot move according to secCheck, so revert to primCheck which worked!
									a.move = primMove;
									slideInfo = primInfo;

									moveInfo.myHitEdge &= ~(.Top|.Bottom); // -> hit x edge, slide along y, so those don't matter (see NOTE)
								}
								else
								{
									// secCheck is the only valid move, and will be applied

									moveInfo.myHitEdge &= ~(.Right|.Left); // -> hit y edge, slide along x, so those don't matter
								}
							}
							else
							{
								// Leave the final moveInfo with only the edge we actually ended up sliding along!

								if (a.move != .Zero)
								{
									if (!xIsPrimaryMove) // INVERTED copy pase from below!
										moveInfo.myHitEdge &= ~(.Right|.Left); // -> hit y edge, slide along x, so those don't matter
									else moveInfo.myHitEdge &= ~(.Top|.Bottom); // -> hit x edge, slide along y, so those don't matter
								}
								else slideInfo = .(); // No sliding took place! (and so leave both hitEdges registered)
							}

							// When we already had a clear preference to one side in the movement, doing the second check was necessary
							// and therefore this result can just be applied without further checks
						}
						else
						{
							// Leave the final moveInfo with only the edge we actually ended up sliding along!

							if (xIsPrimaryMove)
								moveInfo.myHitEdge &= ~(.Right|.Left); // -> hit y edge, slide along x, so those don't matter
							else moveInfo.myHitEdge &= ~(.Top|.Bottom); // -> hit x edge, slide along y, so those don't matter
						}

						a.move += establishedMove; // Add back onto confirmed slide move to get the full movement
					default:
						slideInfo = .();
					}
				}

				if (componentManager.GetComponentOptional<CollisionMoveFeedback>(e, let collFeedback))
				{
					collFeedback.moveCollision = moveInfo;
					collFeedback.slideCollision = slideInfo;
				}

				// Actually move
				aTra.position += a.move;
			}

#if DEBUG
			if (dbgLastMoveCheckedRects.Count > dbgRectCount)
				dbgLastMoveCheckedRects.RemoveRange(0, dbgRectCount);
#endif
		}

		[Inline]
		void DoSlide(Entity e, ref ResolveSet a, Point2 slideMove, out CollisionInfo slideInfo, GridSystem gridSys)
		{
			let establishedMove = a.move; // Save this here for later

			// Set up for slide simulate, pseudo-move to already confirmed position
			a.pos += a.move;
			a.move = slideMove;

			CheckMove(e, ref a, out slideInfo, gridSys);

			a.move += establishedMove; // Add back onto confirmed slide move to get the full movement
		}

		[Optimize]
		void CheckMove(Entity eMove, ref ResolveSet a, out CollisionInfo aInfo, GridSystem gridSys)
		{
			var moverPathRect = MakePathRect(a);

			aInfo = .();

			Entity eHit = 0;
			CollisionInfo bInfo = .();

			CHECKENT:for (let eOther in entities)
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
						// -> DEF a test to figure out the direction of the movers, and if their directions dont interfere / are opposite, just ignore
						// 	-> also need to handle contacts differently, since after their own resolve, they might be anywhere inside their moveRect

						// do we just need to get the overlap rect of their move rects, then look at if they actually both move towards it (or their end position still overlap).
						// if they move in the same direction, we need to call a recursive function (prob move content of outer loop in one)
						//	to move that first!, then us to not overlap and make sure their move is valid (they actaully move where the plan to)
						// when we know they will confront on the other hand, .. what exactly then?

						// i guess we could approximate by just letting the one that moves further take all overlapping space? in most cases its probably just one pixel anyway
						// YEAH thats fair, i mean we also fail to do sliding proberly after the distance is too high

						// -> comment both of those limitations in movement at both places in the code, delete this after work is done.
						// ACTUALLY, NO: we *should* still make it so it only slides as far as the edge goes, then repeat the move/slide loop until both
						// move and slide hit or the movement of one axis is completely done
						// -> similarly, here we WILL need to cover this properly

						// everything has a distance it moves. Everything moves that distance during the same time, which means that
						// the distance alone affects the "speed" of it. we shot make it so that both movers have moved the
						// same percentage of their move ("same time"), and then see how far that makes both move
						// -> make a formular and solve for the percentage, and then apply. sketches should help
						//  -> also add the earlier mover to some sort of list and restore the lost movement in the case
						//     that this is the final obstacle, since the other one might not be able to actually move that distance
						//     or evaluate it here aswell
					}

					bool moveChanged = false;
					for (let aColl in a.coll)
					{
						let aRect = Rect(a.pos + aColl.rect.Position, aColl.rect.Size);
						for (let bColl in b.coll)
							if (aColl.layer.Overlaps(bColl.layer))
							{
#if DEBUG
								bool dbgColliderEntered = false;
#endif
								let bRect = Rect(b.pos + bColl.rect.Position, bColl.rect.Size);

								CHECK:do if (!aRect.Overlaps(bRect) // Do not get stuck when already inside
									&& CheckRects(aRect, bRect, a.move, let hitPercent, let newHitEdge))
								{
									if ((aColl.solid & newHitEdge) == 0 || (bColl.solid & newHitEdge.Inverse) == 0)
									{
#if DEBUG
										dbgColliderEntered = true; // We entered the collider through a non-solid edge
#endif
										break CHECK;
									}

#if DEBUG
									dbgLastMoveCheckedRects.Add(bRect);
#endif

									aInfo = .()
										{
											iWasMoving = true,
											myHitEdge = newHitEdge,
											myColliderIndex = @aColl.[Inline]Index,
											myDir = ((Vector2)a.move).Normalize(),

											other = eOther,
											otherWasMoving = otherMoving,
											otherColliderIndex = @bColl.[Inline]Index,
											otherDir = ((Vector2)b.move).Normalize(),
											otherColliderType = .Rect
										};

									if (componentManager.GetComponentOptional<CollisionReceiveFeedback>(eOther, ?))
									{
										eHit = eOther;
										bInfo = .()
											{
												iWasMoving = otherMoving,
												myHitEdge = newHitEdge.Inverse,
												myColliderIndex = @bColl.[Inline]Index,
												myDir = ((Vector2)b.move).Normalize(),

												other = eMove,
												otherWasMoving = true,
												otherColliderIndex = @aColl.[Inline]Index,
												otherDir = ((Vector2)a.move).Normalize(),
												otherColliderType = .Rect
											};
									}
									
									a.move = ((Vector2)a.move * hitPercent).Round();

									moveChanged = true;
								}
#if DEBUG
								else dbgColliderEntered = true; // We were already inside that collider before moving

								Debug.Assert(dbgColliderEntered || !Rect(a.pos + a.move + aColl.rect.Position, aColl.rect.Size).Overlaps(bRect), "Mover entered collider illegally.");
#endif
								if (a.move == .Zero)
									break CHECKENT;
							}
					}

					if (moveChanged)
					{
						// Update pathRect based on new move
						moverPathRect = MakePathRect(a);
					}
				}
			}

			if (a.move != .Zero)
				CHECKGRID:for (let eOther in gridSys.entities)
				{
					if (eMove == eOther)
						continue; // b is not a!
	
					let bGri = componentManager.GetComponent<GridCollider>(eOther);
					let bTra = componentManager.GetComponent<Transform>(eOther);
					
					let bPos = bTra.position.Round();
					let checkRect = bGri.GetBounds(bPos);
	
					if (moverPathRect.Overlaps(checkRect))
					{
						let bounds = bGri.GetCellBounds();
						bool moveChanged = false;
	
						let cellMin = Point2.Max(moverPathRect.Position / bGri.cellSize, bounds.Position);
						let cellMax = Point2.Min((moverPathRect.Position + moverPathRect.Size) / bGri.cellSize, (bounds.Position + bounds.Size)) + .One;

						for (let aColl in a.coll)
							if (aColl.layer.Overlaps(bGri.layer))
							{
								let aRect = Rect(a.pos + aColl.rect.Position, aColl.rect.Size);
								for (var y = cellMin.Y; y < cellMax.Y; y++)
									for (var x = cellMin.X; x < cellMax.X; x++)
										if (bGri.cells[y][x])
										{
#if DEBUG
											bool dbgColliderEntered = false;
#endif
											let bRect = bGri.GetCollider(x, y, bPos);
	
											CHECK:do if (!aRect.Overlaps(bRect) // Do not get stuck when already inside
												&& CheckRects(aRect, bRect, a.move, let hitPercent, let newHitEdge))
											{
												if ((aColl.solid & newHitEdge) == 0)
												{
#if DEBUG
													dbgColliderEntered = true; // We entered the collider through a non-solid edge
#endif
													break CHECK;
												}

#if DEBUG
												dbgLastMoveCheckedRects.Add(bRect);
#endif
	
												aInfo = .()
													{
														iWasMoving = true,
														myHitEdge = newHitEdge,
														myColliderIndex = @aColl.[Inline]Index,
														myDir = ((Vector2)a.move).Normalize(),
	
														other = eOther,
														otherWasMoving = false,
														otherColliderIndex = GridCollider.GetGridIndex(x, y),
														otherDir = .Zero,
														otherColliderType = .Grid
													};
	
												if (componentManager.GetComponentOptional<CollisionReceiveFeedback>(eOther, ?))
												{
													eHit = eOther;
													bInfo = .()
														{
															iWasMoving = false,
															myHitEdge = newHitEdge.Inverse,
															myColliderIndex = GridCollider.GetGridIndex(x, y),
															myDir = .Zero,
	
															other = eMove,
															otherWasMoving = true,
															otherColliderIndex = @aColl.[Inline]Index,
															otherDir = ((Vector2)a.move).Normalize(),
															otherColliderType = .Rect
														};
												}
												
												a.move = ((Vector2)a.move * hitPercent).Round();

												moveChanged = true;
											}
#if DEBUG
											else dbgColliderEntered = true; // We were already inside that collider before moving
	
											Debug.Assert(dbgColliderEntered || !Rect(a.pos + a.move + aColl.rect.Position, aColl.rect.Size).Overlaps(bRect), "Mover entered collider illegally.");
#endif
											if (a.move == .Zero)
												break CHECKGRID;
										}
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
				if (b.Right <= a.Left) return false; // a is already right of b
				if (b.Right > a.Left) outPercent = Math.Min((a.Left - b.Right) / -(float)movement.X, outPercent); // a is inside or left of b

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
				if (b.Left >= a.Right) return false; // a is already left of b
				if (b.Left < a.Right) outPercent = Math.Min((a.Right - b.Left) / -(float)movement.X, outPercent); // a is inside or right of b

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
				if (b.Bottom <= a.Top) return false; // a is already under b
				if (b.Bottom > a.Top) outPercent = Math.Min((a.Top - b.Bottom) / -(float)movement.Y, outPercent); // a is inside or above b

				if (a.Bottom <= b.Top) // a is above b
				{
					overlapPercent.Y = (a.Bottom - b.Top) / -(float)movement.Y;
					hitPercent = Math.Max(overlapPercent.Y, hitPercent);
					if (overlapPercent.X == overlapPercent.Y)
						hitEdge |= Edge.Bottom;
					else hitEdge = Edge.Bottom;
				}
			}
			// a moves up
			else if (movement.Y < 0)
			{
				if (b.Top >= a.Bottom) return false; // a is already above b
				if (b.Top < a.Bottom) outPercent = Math.Min((a.Bottom - b.Top) / -(float)movement.Y, outPercent); // a is inside or under b

				if (a.Top >= b.Bottom) // a is under b
				{
					overlapPercent.Y = (a.Top - b.Bottom) / -(float)movement.Y;
					hitPercent = Math.Max(overlapPercent.Y, hitPercent);
					if (overlapPercent.X == overlapPercent.Y)
						hitEdge |= Edge.Top;
					else hitEdge = Edge.Top;
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
		public static Rect MakePathRect(ResolveSet s)
		{
			let pos = s.pos;
			var origin = pos;
			var size = Point2.Zero;

			// Get bounds
			for (let coll in s.coll)
			{
				let boxOrig = pos + coll.rect.Position;

				// Leftmost corner
				if (boxOrig.X < origin.X)
					origin.X = boxOrig.X;
				if (boxOrig.Y < origin.Y)
					origin.Y = boxOrig.Y;

				// Size
				let boxSize = coll.rect.Size;
				if (boxOrig.X + boxSize.X > origin.X + size.X)
					size.X = boxSize.X;
				if (boxOrig.Y + boxSize.Y > origin.Y + size.Y)
					size.Y = boxSize.Y;
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
