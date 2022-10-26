using System;
using System.Collections;
using Pile;
using Bon;

namespace Dimtoo
{
	class BucketSystem : ComponentSystem, IRendererSystem
	{
		static Type[?] wantsComponents = .(typeof(Transform), typeof(CollisionBody));
		this
		{
			signatureTypes = wantsComponents;
		}

		public CollisionSystem collSys;
		public bool debugRenderBucket;

		public const int BUCKET_SIZE = 256;
		const int MAX_BUCKET_ENTITIES = 256;
		public Dictionary<Point2, SizedList<Entity, const MAX_BUCKET_ENTITIES>> buckets = new .() ~ delete _;

		public float GetRenderLayer() => 19;

		[PerfTrack("Dimtoo:DebugRender")]
		public void Render(Batch2D batch)
		{
			if (!debugRenderBucket)
				return;
			
			let centerBucket = WorldToBucket(scene.camFocus.Point);
			batch.HollowRect(.(centerBucket * BUCKET_SIZE, .(BUCKET_SIZE)), 1, .LightGray);
		}

		public void Sort()
		{
			buckets.Clear();

			for (let e in entities)
			{
				if (scene.GetComponentOptional<CollisionReceiveFeedback>(e, let feedback))
					feedback.collisions.Clear();

				// Put in buckets!
				let cob = scene.GetComponent<CollisionBody>(e);
				let tra = scene.GetComponent<Transform>(e);

				// TODO Not sure if we should have separate buckets for tags vs layers at some point...
				// -> just needs the one, trigger just the other, seldomly both...
				let bounds = CollisionSystem.MakeColliderBounds(tra.point, cob.colliders, .All, .All);

				let maxBucket = WorldToBucket(bounds.BottomRight);
				let minBucket = WorldToBucket(bounds.TopLeft);
				for (var y = minBucket.Y; y <= maxBucket.Y; y++)
					for (var x = minBucket.X; x <= maxBucket.X; x++)
					{
						let bucket = Point2(x, y);
						let res = buckets.TryGetRef(bucket, ?, var list);
						if (!res)
						{
							buckets.TryAdd(bucket, ?, out list);
							*list = default;
						}

						list.Add(e);
					}
			}
		}

		public static Point2 WorldToBucket(Point2 worldPos)
		{
			Point2 bucket = Point2.Zero;

			if (worldPos.X < 0) bucket.X = (worldPos.X + 1) / BUCKET_SIZE - 1;
			else bucket.X = worldPos.X / BUCKET_SIZE;

			if (worldPos.Y < 0) bucket.Y = (worldPos.Y + 1) / BUCKET_SIZE - 1;
			else bucket.Y = worldPos.Y / BUCKET_SIZE;

			return bucket;
		}

		public static Point2 WorldToBucketRemainder(Point2 worldPos)
		{
			Point2 bucket = Point2.Zero;

			bucket.X = worldPos.X % BUCKET_SIZE;
			if (bucket.X < 0)
				bucket.X += BUCKET_SIZE;

			bucket.Y = worldPos.Y % BUCKET_SIZE;
			if (bucket.Y < 0)
				bucket.Y += BUCKET_SIZE;

			return bucket;
		}
	}
}