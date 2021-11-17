using System;
using Pile;

namespace Dimtoo
{
	struct PhysicsBodyComponent
	{
		public float friction = 0.1f;
		public float mass = 0.1f;
		public Vector2 velocity;
	}

	class PhysicsSystem : ComponentSystem
	{
		static Type[?] wantsComponents = .(typeof(CollisionBodyComponent), typeof(PhysicsBodyComponent));
		this
		{
			signatureTypes = wantsComponents;
		}
	}
}
