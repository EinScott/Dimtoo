using System;

namespace Dimtoo
{
	public struct Animation
	{
		public readonly StringView Name;
		public readonly int From;
		public readonly int To;

		public this(int from, int to, String name)
		{
			From = from;
			To = to;
			Name = name;
		}	
	}
}
