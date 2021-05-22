using Pile;

namespace Dimtoo
{
	[EntityLimited]
	class Transform : Component
	{
		public Vector2 Position;
		public Vector2 Scale = .One;
		public float Rotation;
	}
}
