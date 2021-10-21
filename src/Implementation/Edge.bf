using System;
using Pile;

namespace Dimtoo
{
	enum Edge : uint8
	{
		case Top = 1;
		case Bottom = 1 << 1;
		case Left = 1 << 2;
		case Right = 1 << 3;

		case All = Top | Bottom | Left | Right;
		case None = 0;

		[Inline]
		public Edge Inverse => {
			Edge res = ?;
			switch (this)
			{
			case .Left:
				res = .Right;
			case .Right:
				res = .Left;
			case .Top:
				res = .Bottom;
			case .Bottom:
				res = .Top;
			case .All:
				res = None;
			case .None:
				res = .All;
			}

			res
		}
	}
}