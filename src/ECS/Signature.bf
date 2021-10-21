using System;

namespace Dimtoo
{
	struct Signature : uint64
	{
		[Inline]
		public void Add(uint8 bit) mut
		{
			this |= (1 << bit);
		}

		[Inline]
		public void Remove(uint8 bit) mut
		{
			this = this & ~(1 << bit);
		}
	}
}
