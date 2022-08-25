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
			this.lifetime = SecondsToTicks!(lifetime);
			this.destroyAfterLifetime = destroyAfterLifetime;
		}

		public int lifetime;
		public bool destroyAfterLifetime;
	}

	class LifetimeSystem : ComponentSystem, ITickSystem
	{
		static Type[?] wantsComponents = .(typeof(Lifetime));
		this
		{
			signatureTypes = wantsComponents;
		}

		public void Tick()
		{
			for (let e in entities)
			{
				let lit = scene.GetComponent<Lifetime>(e);

				if (lit.lifetime > 0)
					lit.lifetime--;

				if (lit.lifetime <= 0 && lit.destroyAfterLifetime)
					scene.DeferDestroyEntity(e);
			}
		}
	}
}