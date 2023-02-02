using Pile;
using System;
using Bon;
using System.Diagnostics;

namespace Dimtoo
{
	[BonTarget,BonPolyRegister]
	struct Transform
	{
		public Point2 point;
		[BonInclude]
		Vector2 remainder;

		public Vector2 scale;
		public float rotation;

		public Vector2 Remainder
		{
			[Inline]
			get => remainder;
			[Inline]
			set mut
			{
				remainder = value;

#if DEBUG
				Debug.Assert(remainder.ToRounded() == .Zero);
#endif
			}
		}
		[Inline]
		public Vector2 Position => .(point.X + remainder.X, point.Y + remainder.Y);

		/// Not for movement, just setting of position for jumps/teleports and stuff
		[Inline]
		public void SetPosition(Vector2 position) mut
		{
			point = position.ToRounded();
			remainder = position - point;

#if DEBUG
			Debug.Assert(remainder.ToRounded() == .Zero);
#endif
		}

		[Inline]
		public void AddPosition(Vector2 add) mut
		{
			(let addPoint, let fullRemainder) = ComputeAddPosition(add);

			point += addPoint;
			remainder = fullRemainder;

#if DEBUG
			Debug.Assert(remainder.ToRounded() == .Zero);
#endif
		}

		public (Point2 addPoint, Vector2 fullRemainder) ComputeAddPosition(Vector2 add) mut
		{
			var addPoint = add.ToRounded();
			var fullRemainder = remainder + (add - addPoint);
			if (Math.Round(Math.Abs(fullRemainder.X)) >= 1 || Math.Round(Math.Abs(fullRemainder.Y)) >= 1)
			{
				let rounded = fullRemainder.ToRounded();
				addPoint += rounded;
				fullRemainder -= rounded;

				// Guarantees we dont have a value of (0.5 - 1) in here (which would round the other way)
				fullRemainder = Vector2.Clamp(fullRemainder, .(-0.499f), .(0.499f));
			}

			return (addPoint, fullRemainder);
		}

		public this() { this = default; scale = .One; }
		public this(Vector2 position, Vector2 scale = .One, float rotation = 0)
		{
			this = ?; // We set every field, trust us
			SetPosition(position);
			this.scale = scale;
			this.rotation = rotation;
		}
	}
}
