using System;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	[BonTarget,BonPolyRegister]
	struct Lifetime
	{
		[Inline]
		public this(float lifetime, bool destroyAfterLifetime = true)
		{
			this.lifetime = lifetime;
			this.destroyAfterLifetime = destroyAfterLifetime;
		}

		public float lifetime;
		public bool destroyAfterLifetime;
	}

	class LifetimeSystem : ComponentSystem, ITickSystem
	{
		static Type[?] wantsComponents = .(typeof(Lifetime));
		this
		{
			signatureTypes = wantsComponents;
		}

		public Scene scene;

		public void Tick()
		{
			Debug.Assert(scene != null);

			for (let e in entities)
			{
				let lit = scene.GetComponent<Lifetime>(e);

				if (lit.lifetime > 0)
					lit.lifetime -= Time.Delta;

				if (lit.lifetime <= 0 && lit.destroyAfterLifetime)
					scene.DeferDestroyEntity(e);
			}
		}
	}
}