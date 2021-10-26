using System;

namespace Dimtoo
{
	// @report: this was Signature : uint64 directly before, but this |= x didnt actually affect it
	struct Signature
	{
		uint64 val;

		[Inline]
		public void Add(uint8 bit) mut
		{
			val |= (1 << bit);
		}

		[Inline]
		public void Remove(uint8 bit) mut
		{
			val = val & ~(1 << bit);
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
