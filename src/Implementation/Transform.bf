using Pile;

namespace Dimtoo
{
	struct Transform
	{
		public Vector2 position;
		public Vector2 scale;
		public float rotation;

		public this() { this = default; scale = .One; }
		public this(Vector2 position, Vector2 scale = .One, float rotation = 0)
		{
			this.position = position;
			this.scale = scale;
			this.rotation = rotation;
		}
	}
}
