using System;
using System.Diagnostics;
using Pile;
using System.Collections;

namespace Dimtoo
{
	// - triggers system! -- seperate system to operate after all the movement is over -> each component will know from state if an overlap is new or old!

	// TODO: collision masks / layers / matrix
	// - do old "edges system" to make certain ones passable

	// !! if we have a contact in the direction we're currently moving in, even if we dont trigger a collision (due to rounding / floats),
	//    always report one, cause that makes more sense

	// TODO: second physics system vs this system problem: what do we do if we want to push something?
	// solution:
	// -> we just gather movement info here, we just make sure no moves are invalid
	// -> the physics system should take this info about contacts and collision, and just adjust the moves it makes us do accordingly?
	// 	- if there would be multiple pushes across one frame, but taking multiple cycles here, maybe we need some prediction based on moverect??
	//		-> maybe multiple pyhs update / move - cycles per update?

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
		case Rect(int count, ColliderRect[16] colliders);
		case Grid(Point2 offset, uint8 cellX, uint8 cellY, bool[32*32] collide);

		public Rect GetRectByIndex(int index)
		{
			// TODO: depending on grid, interpret the index given and give back the coresponding rect.
			// probably also put the function that somehow makes an index out of a rect from the collider here somehow, maybe even dependant on grid type
			switch (this)
			{
			case .Rect(let count,let colliders):
			case .Grid(let offset,let cellX,let cellY,let collide):
			}

			return default;
		}

		public Rect this[int index] =>
		{
			Rect res = .();
			switch (this)
			{
			case .Rect(let count,let colliders):
			case .Grid(let offset,let cellX,let cellY,let collide):
			}
			res // TODO
		}
	}

	struct ColliderRect
	{
		public this(Rect rect, Edge solid = .All)
		{
			this.rect = rect;
			this.solid = solid;
		}

		public Rect rect;
		public Edge solid;
	}

	// TODO: feedback stuff (optionals)

	// Feedback of a body's own movement collision "it collides into something else"
	struct CollisionMoveFeedback
	{
		public CollisionInfo moveCollision;
		public CollisionInfo slideCollision;

		// TODO: helper methods here and below to make looking at this, or looking at any of these easier!
	}

	// Feedback of a body's received collision "something else collides into it"
	struct CollisionReceiveFeedback
	{
		public int collisionCount;
		public CollisionInfo[16] collisions;
	}

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

				switch (cob.collider)
				{
				case .Grid(let offset,let cellX,let cellY,let collide):
					let origin = tra.position.Round() + offset;
					Point2 size = .(cellX, cellY);
					for (let y < 32)
						for (let x < 32)
							if (collide[y*32+x])
								batch.HollowRect(.((origin + .(x*cellX,y*cellY)), size), 1, .Red);
				case .Rect(let count,let rects):
					for (let i < count)
					{
						let coll = rects[i];
						batch.HollowRect(.(tra.position.Round() + coll.rect.Position, coll.rect.Size), 1, .Red);
					}
				}

				if (cob.move != .Zero)
					batch.Line(tra.position, tra.position + cob.move, 1, .Magenta);

				batch.HollowRect(MakePathRect(PrepareResolveSet(tra, cob, ?)), 1, .Gray);
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

		[PerfTrack]
		public void Resolve()
		{
			for (let eMove in entities)
			{
				let aCob = componentManager.GetComponent<CollisionBody>(eMove);
				let aTra = componentManager.GetComponent<Transform>(eMove);

				// Make the resolve set for a, also manage a's remainder position when deciding integer position and movement
				var a = PrepareResolveSet(aTra, aCob, out aTra.position); // Put this into our transform to process subpixel movements
				aCob.move = .Zero;

				if (a.move == .Zero)
					continue; // a must move!

				// Move info
				//CollisionInfo info = .();

				Point2 currMove = a.move;
				CheckMove(eMove, ref a, let hitEdge);

				Point2 slideMove = ?;
				bool doSlide = true;
				switch (hitEdge)
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

				if (doSlide)
				{
					currMove = a.move; // Save this here for later

					// Set up for slide simulate, pseudo-move to already confirmed position
					a.pos += a.move;
					a.move = slideMove;

					CheckMove(eMove, ref a, let slideHitEdge);

					a.move += currMove; // Add back onto confirmed slide move to get the full movement
				}

				// Actually move
				aTra.position += a.move;
			}
		}

		void CheckMove(Entity eMove, ref ResolveSet a, out Edge hitEdge)
		{
			var moverPathRect = MakePathRect(a);

			float hitPercent = 1;
			hitEdge = .None;

			for (let eMove2 in entities)
			{
				if (eMove == eMove2)
					continue; // b is not a!

				let bCob = componentManager.GetComponent<CollisionBody>(eMove2);
				let bTra = componentManager.GetComponent<Transform>(eMove2);

				let b = PrepareResolveSet(bTra, bCob, ?);
				let checkPathRect = MakePathRect(b);

				// If they overlap the moveRect
				if (moverPathRect.Overlaps(checkPathRect))
				{
					if (b.move != .Zero)
						{}// TODO: how do we handle moving b that moves?
					// we will probably (since the movements here are "instant" / all made in the same amount of time) just move both to the same percentage until it works? -- some fancy math?
					// -> DEF a test to figure out the direction of the movers, and if their directons dont interfere / are opposite, just ignore
					// 	-> also need to handle contacts differently, since after their own resolve, they might be anywhere inside their moveRect

					bool moveChanged = false;
					switch ((a.coll, b.coll))
					{
					case (.Rect(let aCount, let aRects), .Rect(let bCount,let bRects)):
						for (let ai < aCount)
							for (let bi < bCount)
							{
#if DEBUG								
								bool enteredCollider = false;
#endif

								let aRect = Rect(a.pos + aRects[ai].rect.Position, aRects[ai].rect.Size);
								let bRect = Rect(b.pos + bRects[bi].rect.Position, bRects[bi].rect.Size);
								CHECK:do if (!aRect.Overlaps(bRect) // Do not get stuck when already inside
									&& CheckRects(aRect, bRect, a.move, let newHitPercent, let newHitEdge)
									&& newHitPercent < hitPercent)
								{
									if ((aRects[ai].solid & newHitEdge) == 0 || (bRects[bi].solid & newHitEdge.Inverse) == 0)
									{
#if DEBUG
										enteredCollider = true; // We entered the collider through a non-solid edge
#endif
										break CHECK;
									}

									hitEdge = newHitEdge;
									hitPercent = newHitPercent;
									a.move = ((Vector2)a.move * hitPercent).Round();

									moveChanged = true;
								}
#if DEBUG
								else enteredCollider = true; // We were already inside that collider before moving

								Debug.Assert(enteredCollider || !Rect(a.pos + a.move + aRects[ai].rect.Position, aRects[ai].rect.Size).Overlaps(bRect), "Mover entered collider illegally.");
#endif
							}
					case (.Rect(let count, let rects), .Grid(let offset,let cellX,let cellY,let collide)):
						// TODO
					default: Debug.FatalError("Collider movement not implemented");
					}

					if (moveChanged)
					{
						// Update pathRect based on new move
						moverPathRect = MakePathRect(a);
					}
				}
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
			case .Grid(let offset,let cellX,let cellY,let collide):
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
			case .Rect(let count, let colliders):
				for (let i < Math.Min(count, colliders.Count))
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
