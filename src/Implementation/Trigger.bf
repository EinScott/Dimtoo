using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	typealias TriggerList = SizedList<TriggerEntry, const 4>;

	[BonTarget,BonPolyRegister]
	struct TriggerBody
	{
		public TriggerList triggerEntries;

		public this(params Trigger[] colls)
		{
			this = default;

			for (let i < colls.Count)
				triggerEntries.Add(TriggerEntry() {trigger = colls[i]});
		}
	}

	[BonTarget]
	struct TriggerEntry
	{
		public Trigger trigger;
		public bool checkObstruction;
		public Mask obstructTag = .All;

		// Entries are all sorted by distance to trigger center

		public SizedList<TriggerOverlapInfo, const 32> overlaps;
		public SizedList<TriggerOverlapInfo, const 32> prevOverlaps;

		public SizedList<TriggerOverlapInfo, const 32> newOverlaps;
	}

	[BonTarget]
	struct TriggerOverlapInfo
	{
		public Entity other;
		public uint8 otherColliderIndex;
		public float distance;
	}

	[BonTarget]
	enum TriggerShape
	{
		case Rect(Rect rect);
		case Circle(Point2 position, int radius);
	}

	[BonTarget]
	struct Trigger
	{
		public this(Rect rect, Mask tag)
		{
			this.shape = .Rect(rect);
			this.tag = tag; // By default on layer 0
		}

		public this(TriggerShape shape, Mask tag)
		{
			this.shape = shape;
			this.tag = tag; // By default on layer 0
		}

		public TriggerShape shape;
		public Mask tag;
	}

	[BonTarget,BonPolyRegister]
	struct TriggerOverlapFeedback
	{
		public SizedList<TriggerCollisionInfo, const 8> overlaps;
		public SizedList<TriggerCollisionInfo, const 8> newOverlaps;
	}

	[BonTarget]
	struct TriggerCollisionInfo
	{
		public Entity other;
		public uint8 myColliderIndex, otherColliderIndex;
		public float distance;
	}

	class TriggerFeedbackSystem : ComponentSystem
	{
		static Type[?] wantsComponents = .(typeof(TriggerOverlapFeedback));
		this
		{
			signatureTypes = wantsComponents;
		}

		public void TickPreTriggerSys()
		{
			// To be triggered before TriggerSystem!

			for (let e in entities)
			{
				let feed = scene.GetComponent<TriggerOverlapFeedback>(e);

				// Reset overlaps
				feed.overlaps.Clear();
				feed.newOverlaps.Clear();
			}
		}
	}

	class TriggerSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(Transform), typeof(TriggerBody));
		this
		{
			signatureTypes = wantsComponents;
		}

		public float GetRenderLayer()
		{
			return 20;
		}

		public bool debugRenderTriggers;

		[PerfTrack("Dimtoo:DebugRender")]
		public void Render(Batch2D batch)
		{
			if (!debugRenderTriggers)
				return;

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let trib = scene.GetComponent<TriggerBody>(e);

				for (let entry in trib.triggerEntries)
				{
					switch (entry.trigger.shape)
					{
					case .Rect(let rect): batch.HollowRect(.(tra.point + rect.Position, rect.Size), 1, .Blue);
					case .Circle(let position, let radius): batch.HollowCircle(tra.point + position, radius, 1, 24, .Blue);
					}

					for (let overlap in entry.overlaps)
						batch.HollowCircle(scene.GetComponent<Transform>(overlap.other).point, 4, 1, 4, .Cyan);
				}
			}
		}

		[PerfTrack] // 0.09/0.10 ms before
		public void TickPostColl(BucketSystem buckSys, GridSystem gridSys)
		{
			// We assume to be called after movement has taken place, otherwise updating triggers wouldn't make sense
			// i.e.: (various updates adding force, setting movement) -> collision tick & other movement finalizing things
			//		 -> trigger tick -> ... (movement & now also contact info fresh for next cycle)

			for (let e in entities)
			{
				let tra = scene.GetComponent<Transform>(e);
				let trib = scene.GetComponent<TriggerBody>(e);

				for (var record in ref trib.triggerEntries)
				{
					record.prevOverlaps = record.overlaps;
					record.overlaps.Clear();
				}

				let triggerBounds = MakeColliderBounds(tra.point, trib.triggerEntries);
				let triggerMask = MakeCombinedTagMask(trib.triggerEntries);
				let xMaxBucket = triggerBounds.Right / BucketSystem.BUCKET_SIZE;
				let yMaxBucket = triggerBounds.Bottom / BucketSystem.BUCKET_SIZE;
				CHECKENT:for (var y = triggerBounds.Top / BucketSystem.BUCKET_SIZE; y <= yMaxBucket; y++)
					for (var x = triggerBounds.Left / BucketSystem.BUCKET_SIZE; x <= xMaxBucket; x++)
					{
						let bucket = Point2(x, y);
						if (!buckSys.buckets.ContainsKey(bucket))
							continue;

						for (let eCollision in buckSys.buckets[bucket])
						{
							if (eCollision == e)
								continue;

							let traC = scene.GetComponent<Transform>(eCollision);
							let cob = scene.GetComponent<CollisionBody>(eCollision);

							let collBounds = CollisionSystem.MakeColliderBounds(traC.point, cob.colliders, .None, triggerMask);
							if (!triggerBounds.Overlaps(collBounds))
								continue;

							CHECKTRIG:for (let entry in trib.triggerEntries)
							{
								for (var info in ref trib.triggerEntries[@entry.Index].overlaps)
									if (info.other == eCollision)
										continue CHECKTRIG;

								switch (entry.trigger.shape)
								{
								case .Rect(let rect):
									let triggerRect = Rect(tra.point + rect.Position, rect.Size);

									for (let coll in cob.colliders)
										if (entry.trigger.tag.Overlaps(coll.tag))
										{
											let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);

											if (!triggerRect.Overlaps(colliderRect))
												continue;

											let distance = colliderRect.ClampPoint(triggerRect.Center).DistanceTo(triggerRect.Center);

											HandleOverlap(@entry.Index, @coll.Index, distance);
										}

								case .Circle(let position, let radius):
									let triggerPosition = tra.point + position;

									for (let coll in cob.colliders)
										if (entry.trigger.tag.Overlaps(coll.tag))
										{
											let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);
											let distance = colliderRect.ClampPoint(triggerPosition).DistanceTo(triggerPosition);

											if (distance > radius)
												continue;

											HandleOverlap(@entry.Index, @coll.Index, distance);
										}
								}

								void HandleOverlap(int triggerIndex, int otherColliderIndex, float distance)
								{
									Debug.Assert((triggerIndex | otherColliderIndex) <= uint8.MaxValue);
									var trigger = ref trib.triggerEntries[triggerIndex];

									if (trigger.checkObstruction)
									{
										Point2 triggerOffset;
										int range;
										switch (trigger.trigger.shape)
										{
										case .Circle(let position, let radius):
											triggerOffset = position;
											range = radius;
										case .Rect(let rect):
											triggerOffset = rect.Position;
											range = Math.Max(rect.Width, rect.Height); // Too much, but we already know we overlap anyway...
										}

										let origin = tra.point + triggerOffset;
										let info = Raycast(origin, (traC.point + cob.colliders[otherColliderIndex].rect.Position - origin).ToNormalized(), range, trigger.obstructTag, buckSys, gridSys, scene);
										if (info.other != .Invalid && info.distance < distance
											&& (info.other != eCollision || info.other == eCollision && info.otherColliderIndex != otherColliderIndex))
										{
											return;
										}
									}

									var insert = 0;
									for (var i = trigger.overlaps.Count - 1; i >= 0; i--)
									{
										if (trigger.overlaps[[Unchecked]i].distance <= distance)
										{
											insert = i + 1;
											break;
										}
									}

									let info = TriggerOverlapInfo()
										{
											other = eCollision,
											otherColliderIndex = (.)otherColliderIndex,
											distance = distance
										};
									trigger.overlaps.Insert(insert, info);

									if (scene.GetComponentOptional<TriggerOverlapFeedback>(eCollision, let feedback))
									{
										let collInfo = TriggerCollisionInfo()
											{
												other = e,
												otherColliderIndex = (.)triggerIndex,
												myColliderIndex = (.)otherColliderIndex,
												distance = distance
											};
										feedback.overlaps.Add(collInfo);
									}
								}
							}
						}
				}

				for (var record in ref trib.triggerEntries)
				{
					record.newOverlaps.Clear();

					for (let currOver in record.overlaps)
					{
						bool isOld = false;
						for (let prevOver in record.prevOverlaps)
						{
							if (currOver.other == prevOver.other && currOver.otherColliderIndex == prevOver.otherColliderIndex)
								isOld = true;
						}

						// This overlap is new, add it to the new list
						if (!isOld)
						{
							record.newOverlaps.Add(currOver);

							if (scene.GetComponentOptional<TriggerOverlapFeedback>(currOver.other, let feedback))
								// Technically we've already added this to the feedback.overlaps list somewhere, but we're not going to search, just make it again
								feedback.newOverlaps.Add(TriggerCollisionInfo()
									{
										other = e,
										myColliderIndex = currOver.otherColliderIndex,
										otherColliderIndex = (.)@record.Index
									});
						}
					}
				}
			}
		}

		public static TriggerOverlapInfo Raycast(Point2 origin, Vector2 dir, int range, Mask tagMask, BucketSystem buckSys, GridSystem gridSys, Scene scene)
		{
			if (dir == .Zero)
				return default;

			var currBucket = origin / BucketSystem.BUCKET_SIZE;
			let oneOverDir = Vector2(1 / dir.X, 1 / dir.Y);
			let xBucketStep = Math.Sign(dir.X), yBucketStep = Math.Sign(dir.Y);
			
			let endBucket = (origin + dir * range).ToRounded() / BucketSystem.BUCKET_SIZE;
			bool lastBucket = false;
			TriggerOverlapInfo bestOverlap = .() {
				distance = float.MaxValue
			};
			while (!lastBucket)
			{
				if (currBucket == endBucket)
					lastBucket = true;

				// TODO to possibly optimize this, we could try to pass in a list, pre sort entities by distance and only check rays against the ones we already checked nearer to us in the trigger loop
				for (let e in buckSys.buckets[currBucket])
				{
					let traC = scene.GetComponent<Transform>(e);
					let cob = scene.GetComponent<CollisionBody>(e);

					for (let coll in cob.colliders)
					{
						if (tagMask.Overlaps(coll.tag))
						{
							let colliderRect = Rect(traC.point + coll.rect.Position, coll.rect.Size);

							if (CheckRayRect(origin, dir, oneOverDir, colliderRect, let newDist)
								&& newDist < bestOverlap.distance)
							{
								Debug.Assert(newDist > 0);
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

				let bucketBounds = Rect(currBucket.X * BucketSystem.BUCKET_SIZE, currBucket.Y * BucketSystem.BUCKET_SIZE, BucketSystem.BUCKET_SIZE, BucketSystem.BUCKET_SIZE);
				for (let e in gridSys.entities)
				{
					let tra = scene.GetComponent<Transform>(e);
					let gri = scene.GetComponent<Grid>(e);

					if (//gri.layer TODO layer check actually maybe have obstructionLayer not targetTag that makes so much more sense thanks!
						!gri.GetBounds(tra.point).Overlaps(bucketBounds))
						continue;

					(let cellMin, let cellMax) = gri.GetCellBoundsOverlapping(tra.point, bucketBounds);
					for (var y = cellMin.Y; y < cellMax.Y; y++)
						for (var x = cellMin.X; x < cellMax.X; x++)
						{
							if (!gri.cells[y][x].IsSolid)
								continue;
							let tileRect = gri.GetCollider(x, y, tra.point);

							if (CheckRayRect(origin, dir, oneOverDir, tileRect, let newDist)
								&& newDist < bestOverlap.distance)
							{
								Debug.Assert(newDist > 0);
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

		// TODO: dist sometimes negative, hot not detected somtimes too....
		static bool CheckRayRect(Point2 rayOrigin, Vector2 rayDir, Vector2 oneOverDir, Rect rect, out float hitDistance)
		{
			float t1 = (rect.Left - rayOrigin.X) * oneOverDir.X;
			float t2 = (rect.Right - rayOrigin.X) * oneOverDir.X;
			float t3 = (rect.Top - rayOrigin.Y) * oneOverDir.Y;
			float t4 = (rect.Bottom - rayOrigin.Y) * oneOverDir.Y;

			float tmin = Math.Max(Math.Min(t1, t2), Math.Min(t3, t4));
			float tmax = Math.Min(Math.Max(t1, t2), Math.Max(t3, t4));

			// if tmax < 0, ray (line) is intersecting AABB, but the whole AABB is behind us
			if (tmax < 0)
			{
			    hitDistance = tmax;
			    return false;
			}

			// if tmin > tmax, ray doesn't intersect AABB
			if (tmin > tmax)
			{
			    hitDistance = tmax;
			    return false;
			}

			hitDistance = tmin;
			return true;
		}

		public static Mask MakeCombinedTagMask(TriggerList triggers)
		{
			Mask m = default;
			for (let entry in triggers)
				m = m.Combine(entry.trigger.tag);
			return m;
		}

		[Optimize]
		public static Rect MakeColliderBounds(Point2 pos, TriggerList triggers, Mask tagMask = .All)
		{
			var origin = pos;
			var size = Point2.Zero;

			// Get bounds
			for (let entry in triggers)
			{
				if (!entry.trigger.tag.Overlaps(tagMask))
					continue;

				Rect shapeRect;
				switch (entry.trigger.shape)
				{
				case .Rect(let rect): shapeRect = rect;
				case .Circle(let position, let radius): shapeRect = .(position.X - radius, position.Y - radius, radius * 2, radius * 2);
				}

				let boxOrig = pos + shapeRect.Position;

				// Leftmost corner
				if (boxOrig.X < origin.X)
					origin.X = boxOrig.X;
				if (boxOrig.Y < origin.Y)
					origin.Y = boxOrig.Y;

				// Size
				let boxSize = shapeRect.Size;
				if (boxOrig.X + boxSize.X > origin.X + size.X)
					size.X = boxSize.X;
				if (boxOrig.Y + boxSize.Y > origin.Y + size.Y)
					size.Y = boxSize.Y;
			}

			return .(origin, size);
		}
	}
}
