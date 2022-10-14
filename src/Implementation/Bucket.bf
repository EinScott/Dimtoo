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
			
			let centerBucket = scene.camFocus.Point / BUCKET_SIZE;
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

				let xMaxBucket = bounds.Right / BUCKET_SIZE;
				let yMaxBucket = bounds.Bottom / BUCKET_SIZE;
				for (var y = bounds.Top / BUCKET_SIZE; y <= yMaxBucket; y++)
					for (var x = bounds.Left / BUCKET_SIZE; x <= xMaxBucket; x++)
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
	}
}