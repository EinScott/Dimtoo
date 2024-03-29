using System;
using System.Diagnostics;
using Pile;
using System.Collections;
using Bon;

namespace Dimtoo
{
	// Unconventional 2d collision detection & response

	// TODO: second physics system vs this system problem: what do we do if we want to push something?
	// solution:
	// -> we just gather movement info here, we just make sure no moves are invalid
	// -> the physics system should take this info about contacts and collision, and just adjust the moves it makes us do accordingly?
	// 	- if there would be multiple pushes across one frame, but taking multiple cycles here, maybe we need some prediction based on moverect??
	//		-> maybe multiple pyhs update / move - cycles per update?
	//	(or just PreCollTick and PostCollTick) or similar!

	typealias ColliderList = SizedList<ColliderRect, const 4>;

	[BonTarget,BonPolyRegister]
	struct CollisionBody
	{
		public Vector2 move;
		public Vector2 resultingMove;
		public ColliderList colliders;

		public this(ColliderList coll)
		{
			move = .Zero;
			colliders = coll;
			resultingMove = default;
		}

		[Inline]
		public Rect GetCollider(int index)
		{
			Debug.Assert((uint)index < (uint)colliders.Count);
			return colliders[index].rect;
		}
	}

	[BonTarget]
	enum ColliderType
	{
		Rect,
		Grid
	}

	[BonTarget]
	struct Mask
	{
		public const Self None = default;
		public const Self All = .(uint64.MaxValue);

		public this(uint64 mask = 0x1)
		{
			val = mask;
		}

		[BonInclude]
		uint64 val;

		public bool this[int layer]
		{
			[Inline]
			get => (val & (uint64)(1 << layer)) > 0;
			set mut => val |= (uint64)(1 << layer);
		}

		[Inline]
		public bool Overlaps(Mask other) => (val & other.val) > 0;

		[Inline]
		public Mask Combine(Mask other) => .(val | other.val);

		[Inline]
		public static implicit operator Self(uint64 i)
		{
			Mask m = default;
			m.val = i;
			return m;
		}
	}

	[BonTarget]
	struct ColliderRect
	{
		public this(Rect rect, Mask layer = 0x1, Edge solid = .All, Mask tag = 0)
		{
			this.rect = rect;
			this.solid = solid; // By default all edges solid
			this.layer = layer; // By default only on layer 1
			this.tag = tag; // By default no tag
		}

		public Rect rect;
		public Edge solid;
		public Mask layer; // Layers on which this rect collides
		public Mask tag; // Tags for further filtering on external systems like triggers, etc...
	}

	// Feedback of a body's own movement collision "it collides into something else"
	[BonTarget,BonPolyRegister]
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
	[BonTarget,BonPolyRegister]
	struct CollisionReceiveFeedback
	{
		public SizedList<CollisionInfo, const 32> collisions;

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

	[BonTarget]
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

		public float GetRenderLayer()
		{
			return 20; // debug on top
		}

		[PerfTrack("Dimtoo:DebugRender")]
		public void Render(Batch2D batch)
		{
			if (!debugRenderCollisions)
				return;

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let cob = scene.GetComponent<CollisionBody>(e);

				if (cob.move != .Zero)
					batch.Line(tra.point, tra.point + cob.move, 1, .Magenta);

				batch.HollowRect(MakePathRect(PrepareResolveSet(tra, cob)), 1, .Gray);

				for (let coll in cob.colliders)
					batch.HollowRect(.(tra.point + coll.rect.Position, coll.rect.Size), 1, .Red);
			}

#if DEBUG
			for (let r in dbgLastMoveCheckedRects)
				batch.HollowRect(r, 1, .Green);
#endif
		}

		typealias ResolveSet = (ColliderList coll, Point2 move, Point2 pos);

		static ResolveSet PrepareResolveSet(Transform* tra, CollisionBody* body)
		{
			// We move in whole pixels only, so prepare for that here!
			ResolveSet a;
			a.coll = body.colliders;
			a.pos = tra.point;
			a.move = body.move.ToRounded();

			return a;
		}

		[PerfTrack]
#if !DEBUG
		[Optimize]
#endif
		public void Resolve(BucketSystem buckSys, GridSystem gridSys)
		{
#if DEBUG
			let dbgRectCount = dbgLastMoveCheckedRects.Count;
#endif

			for (let e in entities)
			{
				let aCob = scene.GetComponent<CollisionBody>(e);
				let aTra = scene.GetComponent<Transform>(e);

				var a = PrepareResolveSet(aTra, aCob);
				(a.move, var posRemainder) = aTra.ComputeAddPosition(aCob.move);
				aCob.move = .Zero;

				// The position of the entity doesnt change by this, the float remainder would just move the entity in this case
				// and thus we move that onto the movement amount.
				Debug.Assert(a.pos == aTra.point);

				if (a.move == .Zero)
				{
					// Update pos to record subpixel moves
					aCob.resultingMove = posRemainder - aTra.Remainder;
					aTra.Remainder = posRemainder;

					if (scene.GetComponentOptional<CollisionMoveFeedback>(e, let collFeedback))
					{
						// Clear!
						collFeedback.moveCollision = default;
						collFeedback.slideCollision = default;
					}

					continue; // a must move!
				}

				let aPos = a.pos; // a.pos will be modified for further checks, so record it here

				// Move info
				Point2 currMove = a.move;
				CheckMove(e, ref a, var moveInfo, buckSys, gridSys);

				CollisionInfo slideInfo;
				{
					let hitX = ((moveInfo.myHitEdge & .Left) != 0 || (moveInfo.myHitEdge & .Right) != 0);
					let hitY = ((moveInfo.myHitEdge & .Top) != 0 || (moveInfo.myHitEdge & .Bottom) != 0);

					switch ((hitX, hitY))
					{
					case (true, false):
						DoSlide(e, ref a, .(0, currMove.Y), out slideInfo, buckSys, gridSys);
					case (false, true):
						DoSlide(e, ref a, .(currMove.X, 0), out slideInfo, buckSys, gridSys);
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

						CheckMove(e, ref a, out slideInfo, buckSys, gridSys);

						if (a.move == .Zero || equalMove) // Check second one, if first side blocks or we move equally in both directions
						{
							// Save for later compare
							let primInfo = slideInfo;
							let primMove = a.move;

							a.move = secCheck;

							CheckMove(e, ref a, out slideInfo, buckSys, gridSys);

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

				if (scene.GetComponentOptional<CollisionMoveFeedback>(e, let collFeedback))
				{
					collFeedback.moveCollision = moveInfo;
					collFeedback.slideCollision = slideInfo;
				}

				// Based on where we collide, adjust posRemainder to move as close to it as possible. This ensures two things:
				// - when we move back into a collision we immediately collide again (as would be logical)
				// - when we move through remainder rounding but cant, we don't theoretically move back due to the remainder getting inverted
				let hitEdges = moveInfo.myHitEdge | slideInfo.myHitEdge;
				if ((hitEdges & .Left) > 0)
					posRemainder.X = -0.49999f;
				else if ((hitEdges & .Right) > 0)
					posRemainder.X = 0.49999f;
				if ((hitEdges & .Top) > 0)
					posRemainder.Y = -0.49999f;
				else if ((hitEdges & .Bottom) > 0)
					posRemainder.Y = 0.49999f;

				// Actually move
				aCob.resultingMove = a.move + (posRemainder - aTra.Remainder);
				aTra.point = aPos + a.move;
				aTra.Remainder = posRemainder;
			}

#if DEBUG
			if (dbgLastMoveCheckedRects.Count > dbgRectCount)
				dbgLastMoveCheckedRects.RemoveRange(0, dbgRectCount);
#endif
		}

		[Inline]
		void DoSlide(Entity e, ref ResolveSet a, Point2 slideMove, out CollisionInfo slideInfo, BucketSystem buckSys, GridSystem gridSys)
		{
			let establishedMove = a.move; // Save this here for later

			// Set up for slide simulate, pseudo-move to already confirmed position
			a.pos += a.move;
			a.move = slideMove;

			CheckMove(e, ref a, out slideInfo, buckSys, gridSys);

			a.move += establishedMove; // Add back onto confirmed slide move to get the full movement
		}

		[PerfTrack]
#if !DEBUG
		[Optimize]
#endif
		void CheckMove(Entity eMove, ref ResolveSet a, out CollisionInfo aInfo, BucketSystem buckSys, GridSystem gridSys)
		{
			var moverPathRect = MakePathRect(a);
			let moverLayerMath = MakeCombinedLayerMask(a.coll);

			aInfo = .();

			Entity eHit = 0;
			CollisionInfo bInfo = .();

			let maxBucket = BucketSystem.WorldToBucket(moverPathRect.BottomRight);
			let minBucket = BucketSystem.WorldToBucket(moverPathRect.TopLeft);
			CHECKENT:for (var y = minBucket.Y; y <= maxBucket.Y; y++)
				for (var x = minBucket.X; x <= maxBucket.X; x++)
				{
					let bucket = Point2(x, y);
					if (!buckSys.buckets.ContainsKey(bucket))
						continue;

					for (let eOther in buckSys.buckets[bucket])
					{
						if (eMove == eOther)
							continue; // b is not a!
		
						let bCob = scene.GetComponent<CollisionBody>(eOther);
						let bTra = scene.GetComponent<Transform>(eOther);

						let b = PrepareResolveSet(bTra, bCob);
						let checkPathRect = MakePathRect(b, moverLayerMath);
		
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
								{
									if (!aColl.layer.Overlaps(bColl.layer))
										continue;
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
												myDir = ((Vector2)a.move).ToNormalized(),
		
												other = eOther,
												otherWasMoving = otherMoving,
												otherColliderIndex = @bColl.[Inline]Index,
												otherDir = ((Vector2)b.move).ToNormalized(),
												otherColliderType = .Rect
											};
		
										if (scene.GetComponentOptional<CollisionReceiveFeedback>(eOther, ?))
										{
											eHit = eOther;
											bInfo = .()
												{
													iWasMoving = otherMoving,
													myHitEdge = newHitEdge.Inverse,
													myColliderIndex = @bColl.[Inline]Index,
													myDir = ((Vector2)b.move).ToNormalized(),
		
													other = eMove,
													otherWasMoving = true,
													otherColliderIndex = @aColl.[Inline]Index,
													otherDir = ((Vector2)a.move).ToNormalized(),
													otherColliderType = .Rect
												};
										}
										
										a.move = ((Vector2)a.move * hitPercent).ToRounded();
		
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
				}

			if (a.move != .Zero)
				CHECKGRID:for (let eOther in gridSys.entities)
				{
					if (eMove == eOther)
						continue; // b is not a!
	
					let bGri = scene.GetComponent<Grid>(eOther);
					let bTra = scene.GetComponent<Transform>(eOther);
					
					let bPos = bTra.point;
					let checkRect = bGri.GetBounds(bPos);
	
					if (!moverPathRect.Overlaps(checkRect))
						continue;

					bool moveChanged = false;

					(let cellMin, let cellMax) = bGri.GetCellBoundsOverlapping(bPos, moverPathRect);

					for (let aColl in a.coll)
					{
						if (!aColl.layer.Overlaps(bGri.layer))
							continue;

						let aRect = Rect(a.pos + aColl.rect.Position, aColl.rect.Size);
						for (var y = cellMin.Y; y < cellMax.Y; y++)
							for (var x = cellMin.X; x < cellMax.X; x++)
							{
								if (!bGri.cells[y][x].IsSolid)
									continue;
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
											myDir = ((Vector2)a.move).ToNormalized(),

											other = eOther,
											otherWasMoving = false,
											otherColliderIndex = Grid.GetGridIndex(x, y),
											otherDir = .Zero,
											otherColliderType = .Grid
										};

									if (scene.GetComponentOptional<CollisionReceiveFeedback>(eOther, ?))
									{
										eHit = eOther;
										bInfo = .()
											{
												iWasMoving = false,
												myHitEdge = newHitEdge.Inverse,
												myColliderIndex = Grid.GetGridIndex(x, y),
												myDir = .Zero,

												other = eMove,
												otherWasMoving = true,
												otherColliderIndex = @aColl.[Inline]Index,
												otherDir = ((Vector2)a.move).ToNormalized(),
												otherColliderType = .Rect
											};
									}
									
									a.move = ((Vector2)a.move * hitPercent).ToRounded();

									moveChanged = true;
								}
#if DEBUG
								else dbgColliderEntered = true; // We were already inside that collider before moving

								Debug.Assert(dbgColliderEntered || !Rect(a.pos + a.move + aColl.rect.Position, aColl.rect.Size).Overlaps(bRect), "Mover entered collider illegally.");
#endif
								if (a.move == .Zero)
									break CHECKGRID;
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
				let feedback = scene.GetComponent<CollisionReceiveFeedback>(eHit);
				feedback.collisions.Add(bInfo);
			}
		}

		public static TriggerOverlapInfo Raycast(Point2 origin, Vector2 dir, int range, Mask layerMask, BucketSystem buckSys, GridSystem gridSys, Scene scene, Entity ignore = .Invalid)
		{
			if (dir == .Zero)
				return default;

			var currBucket = BucketSystem.WorldToBucket(origin);
			let oneOverDir = Vector2(1 / dir.X, 1 / dir.Y);
			let xBucketStep = Math.Sign(dir.X), yBucketStep = Math.Sign(dir.Y);

			let endBucket = BucketSystem.WorldToBucket((origin + dir * range).ToRounded());
			bool lastBucket = false;
			TriggerOverlapInfo bestOverlap = .() {
				distance = float.MaxValue
			};
			while (!lastBucket)
			{
				if (currBucket == endBucket)
					lastBucket = true;

				// TODO to possibly optimize this, we could try to pass in a list, pre sort entities by distance and only check rays against the ones we already checked nearer to us in the trigger loop
				if (buckSys.buckets.ContainsKey(currBucket))
				{
					for (let e in buckSys.buckets[currBucket])
					{
						if (e == ignore)
							continue;

						let traC = scene.GetComponent<Transform>(e);
						let cob = scene.GetComponent<CollisionBody>(e);

						for (let coll in cob.colliders)
						{
							if (layerMask.Overlaps(coll.layer))
							{
								let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);

								if (CheckRayRect(origin, dir, oneOverDir, colliderRect, let newDist)
									&& newDist < bestOverlap.distance && newDist >= 0 && newDist <= range)
								{
									Debug.Assert(newDist >= 0);
									bestOverlap = TriggerOverlapInfo()
										{
											other = e,
											otherColliderIndex = (.)@coll.Index,
											distance = newDist
										};
								}
							}
						}
					}
				}

				let bucketBounds = Rect(currBucket.X * BucketSystem.BUCKET_SIZE, currBucket.Y * BucketSystem.BUCKET_SIZE, BucketSystem.BUCKET_SIZE, BucketSystem.BUCKET_SIZE);
				for (let e in gridSys.entities)
				{
					let tra = scene.GetComponent<Transform>(e);
					let gri = scene.GetComponent<Grid>(e);

					if (!layerMask.Overlaps(gri.layer)
						|| !gri.GetBounds(tra.point).Overlaps(bucketBounds))
						continue;

					(let cellMin, let cellMax) = gri.GetCellBoundsOverlapping(tra.point, bucketBounds);
					for (var y = cellMin.Y; y < cellMax.Y; y++)
						for (var x = cellMin.X; x < cellMax.X; x++)
						{
							if (!gri.cells[y][x].IsSolid)
								continue;
							let tileRect = gri.GetCollider(x, y, tra.point);

							if (CheckRayRect(origin, dir, oneOverDir, tileRect, let newDist)
								&& newDist < bestOverlap.distance && newDist >= 0 && newDist <= range)
							{
								Debug.Assert(newDist >= 0);
								bestOverlap = TriggerOverlapInfo()
									{
										other = e, // TODO: other type of info here... grid not really specifiable! or not?
										distance = newDist
									};
							}
						}
				}

				// Later bucket's hits will only be further away
				if (bestOverlap.other != .Invalid)
					return bestOverlap;

				// TODO issue with putting planes wrong due to negative coordinates...

				let nextBucketX = currBucket.X + xBucketStep;
				let nextBucketY = currBucket.Y + yBucketStep;
				let nextBucketXNearPlane = xBucketStep > 0 ? nextBucketX * BucketSystem.BUCKET_SIZE : nextBucketX * BucketSystem.BUCKET_SIZE + BucketSystem.BUCKET_SIZE - 1;
				let nextBucketYNearPlane = yBucketStep > 0 ? nextBucketY * BucketSystem.BUCKET_SIZE : nextBucketY * BucketSystem.BUCKET_SIZE + BucketSystem.BUCKET_SIZE - 1;

				let xHitsPlane = CheckRayPlane(origin, dir, .(nextBucketXNearPlane, 0), .(-xBucketStep, 0), let xPlaneDist);
				let yHitsPlane = CheckRayPlane(origin, dir, .(0, nextBucketYNearPlane), .(0, -yBucketStep), let yPlaneDist);
				Debug.Assert(xHitsPlane || yHitsPlane);

				if (xPlaneDist < yPlaneDist)
					currBucket.X += xBucketStep;
				else currBucket.Y += yBucketStep;
			}

			return default;
		}

		// distance returned does not include the rect size, it's the amount by which the rect could move in that dir.
		public static TriggerOverlapInfo Rectcast(Rect rect, Vector2 dir, int range, Mask layerMask, BucketSystem buckSys, GridSystem gridSys, Scene scene, Entity ignore = .Invalid)
		{
			// TODO: this is very similar to CheckMove... also more efficient in theory... maybe use this in there?
			// OPTIMIZE: COULD cycle through chunks against dir, and break if we found something in a chunk when moving to the next... or even just check a ray with some width instead of a rect of chunks!

			if (dir == .Zero)
				return default;

			var bounds = rect;
			let cast = (dir * range).ToRounded();
			bounds.Size += Point2.Abs(cast);
			if (cast.X < 0)
				bounds.X += cast.X;
			if (cast.Y < 0)
				bounds.Y += cast.Y;

			TriggerOverlapInfo bestOverlap = .() {
				distance = float.MaxValue
			};

			let maxBucket = BucketSystem.WorldToBucket(bounds.BottomRight);
			let minBucket = BucketSystem.WorldToBucket(bounds.TopLeft);
			CHECKENT:for (var y = minBucket.Y; y <= maxBucket.Y; y++)
				for (var x = minBucket.X; x <= maxBucket.X; x++)
				{
					let bucket = Point2(x, y);
					if (!buckSys.buckets.ContainsKey(bucket))
						continue;

					for (let e in buckSys.buckets[bucket])
					{
						if (e == ignore)
							continue;

						let cob = scene.GetComponent<CollisionBody>(e);
						let tra = scene.GetComponent<Transform>(e);

						for (let coll in cob.colliders)
						{
							if (layerMask.Overlaps(coll.layer))
							{
								let colliderRect = Rect(tra.point + coll.rect.Position, coll.rect.Size);

								if (CheckRects(rect, colliderRect, cast, let hitPercent, let hitEdge))
								{
									let dist = ((Vector2)cast * hitPercent).Length;
									if (dist <= range)
										bestOverlap = TriggerOverlapInfo()
										{
											other = e,
											otherColliderIndex = (.)@coll.Index,
											distance = dist
										};
								}
							}
						}
					}
				}

			for (let e in gridSys.entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let gri = scene.GetComponent<Grid>(e);

				if (!gri.GetBounds(tra.point).Overlaps(bounds)
					|| !layerMask.Overlaps(gri.layer))
					continue;

				(let cellMin, let cellMax) = gri.GetCellBoundsOverlapping(tra.point, bounds);
				for (var cellY = cellMin.Y; cellY < cellMax.Y; cellY++)
					for (var cellX = cellMin.X; cellX < cellMax.X; cellX++)
					{
						if (!gri.cells[cellY][cellX].IsSolid)
							continue;
						let tileRect = gri.GetCollider(cellX, cellY, tra.point);

						if (CheckRects(rect, tileRect, cast, let hitPercent, let hitEdge))
						{
							let dist = ((Vector2)cast * hitPercent).Length;
							if (dist <= range)
								bestOverlap = TriggerOverlapInfo()
								{
									other = e,
									distance = dist
								};
						}
					}
			}

			return bestOverlap.distance != float.MaxValue ? bestOverlap : default;
		}

		static bool CheckRayPlane(Point2 rayOrigin, Vector2 rayDir, Point2 planePoint, Vector2 planeNormal, out float hitDistance)
		{
			let denominator = Vector2.Dot(planeNormal, rayDir);

			if (Math.Abs(denominator) > 0.0001)
			{
				let difference = planePoint - rayOrigin;
				let t = Vector2.Dot(difference, planeNormal) / denominator;

				if (t > 0.0001)
				{
					hitDistance = t;
					return true;
				}
			}

			hitDistance = float.MaxValue;
			return false;
		}

		static bool CheckRayRect(Point2 rayOrigin, Vector2 rayDir, Vector2 oneOverDir, Rect rect, out float hitDistance)
		{
			float t1 = (rect.Left - rayOrigin.X) * oneOverDir.X;
			float t2 = (rect.Right - rayOrigin.X) * oneOverDir.X;
			float t3 = (rect.Top - rayOrigin.Y) * oneOverDir.Y;
			float t4 = (rect.Bottom - rayOrigin.Y) * oneOverDir.Y;

			float tmin = Math.Max(Math.Min(t1, t2), Math.Min(t3, t4));
			float tmax = Math.Min(Math.Max(t1, t2), Math.Max(t3, t4));

			if (tmax < 0 || tmin < 0
				|| tmin > tmax)
			{
			    hitDistance = float.MaxValue;
			    return false;
			}

			hitDistance = tmin;
			return true;
		}

#if !DEBUG		
		[Optimize]
#endif
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

		public static Mask MakeCombinedLayerMask(ColliderList colliders)
		{
			Mask m = default;
			for (let coll in colliders)
				m = m.Combine(coll.layer);
			return m;
		}

		[Optimize]
		public static Rect MakeColliderBounds(Point2 pos, ColliderList colliders, Mask layer = .All, Mask tag = .None)
		{
			var origin = Point2.Zero;
			var size = Point2.Zero;
			bool first = true;

			// Get bounds
			for (let coll in colliders)
			{
				if (!coll.layer.Overlaps(layer)
					&& !coll.tag.Overlaps(tag))
					continue;

				let boxOrig = pos + coll.rect.Position;

				if (first)
				{
					origin = boxOrig;
					first = false;
				}
				else
				{
					// TopLeft corner shift
					if (boxOrig.X < origin.X)
					{
						size.X += origin.X - boxOrig.X;
						origin.X = boxOrig.X;
					}
					if (boxOrig.Y < origin.Y)
					{
						size.Y += origin.Y - boxOrig.Y;
						origin.Y = boxOrig.Y;
					}
				}

				// BottomRight corner shift
				let boxRight = boxOrig.X + coll.rect.Width;
				if (boxRight > origin.X + size.X)
					size.X = boxRight - origin.X;

				let boxBottom = boxOrig.Y + coll.rect.Height;
				if (boxBottom > origin.Y + size.Y)
					size.Y = boxBottom - origin.Y;
			}

			return .(origin, size);
		}

		[Optimize]
		// For non-mover entities, this just returns bounds
		public static Rect MakePathRect(ResolveSet s, Mask mask = .All)
		{
			var bounds = MakeColliderBounds(s.pos, s.coll, mask);

			// Expand by movement
			if (s.move != .Zero)
			{
				bounds.Size += Point2.Abs(s.move);
				if (s.move.X < 0)
					bounds.X += s.move.X;
				if (s.move.Y < 0)
					bounds.Y += s.move.Y;
			}

			return bounds;
		}
	}
}
