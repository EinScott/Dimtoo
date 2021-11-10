using System;

namespace Dimtoo
{
	struct Signature
	{
		uint64 val;

		[Inline]
		public void Add(ComponentType type) mut
		{
			val |= (1 << type);
		}

		[Inline]
		public void Remove(ComponentType type) mut
		{
			val = val & ~(1 << type);
		}

		[Inline]
		public static implicit operator uint64(Self s) => s.val;

		[Inline]
		public static Self operator &(Self r, Self l)
		{
			Self s = default;
			s.val = r.val & l.val;
			return s;
		}

		[Inline]
		public static Self operator |(Self r, Self l)
		{
			Self s = default;
			s.val = r.val | l.val;
			return s;
		}
	}
}
