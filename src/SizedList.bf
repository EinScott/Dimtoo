using System;
using System.Collections;
using System.Diagnostics;
using Bon;

namespace Dimtoo
{
	[BonTarget]
	struct SizedList<T, Size> : IEnumerable<T> where Size : const int
	{
		// TODO: could integrate this
		[BonInclude]
		int count;
		[BonInclude]
		T[Size] arr;

		[Inline]
		public int Count => count;

		[Inline]
		public int Capacity => Size;

		public ref T this[int index]
		{
			[Checked]
			get mut
			{
				Runtime.Assert((uint)index < (uint)count);
				return ref arr[index];
			}

			[Unchecked, Inline]
			get mut
			{
				return ref arr[index];
			}
		}

		public T this[int index]
		{
			[Checked]
			get
			{
				Runtime.Assert((uint)index < (uint)count);
				return arr[index];
			}

			[Unchecked, Inline]
			get
			{
				return arr[index];
			}
		}

		public ref T this[Index index]
		{
			[Checked]
			get mut
			{
				int idx;
				switch (index)
				{
				case .FromFront(let offset): idx = offset;
				case .FromEnd(let offset): idx = count - offset;
				}
				Runtime.Assert((uint)idx < (uint)count);
				return ref arr[idx];
			}

			[Unchecked, Inline]
			get mut
			{
				int idx;
				switch (index)
				{
				case .FromFront(let offset): idx = offset;
				case .FromEnd(let offset): idx = count - offset;
				}
				return ref arr[idx];
			}
		}

		public T this[Index index]
		{
			[Checked]
			get
			{
				int idx;
				switch (index)
				{
				case .FromFront(let offset): idx = offset;
				case .FromEnd(let offset): idx = count - offset;
				}
				Runtime.Assert((uint)idx < (uint)count);
				return arr[idx];
			}

			[Unchecked, Inline]
			get
			{
				int idx;
				switch (index)
				{
				case .FromFront(let offset): idx = offset;
				case .FromEnd(let offset): idx = count - offset;
				}
				return arr[idx];
			}
		}

		public Span<T> this[IndexRange range]
		{
#if !DEBUG
			[Inline]
#endif
			get
			{
				T* start;
				switch (range.[Friend]mStart)
				{
				case .FromFront(let offset):
					Debug.Assert((uint)offset <= (uint)count);
					start = &arr[offset];
				case .FromEnd(let offset):
					Debug.Assert((uint)offset <= (uint)count);
					start = &arr[count - offset];
				}
				T* end;
				if (range.[Friend]mIsClosed)
				{
					switch (range.[Friend]mEnd)
					{
					case .FromFront(let offset):
						Debug.Assert((uint)offset < (uint)count);
						end = &arr[offset + 1];
					case .FromEnd(let offset):
						Debug.Assert((uint)(offset - 1) <= (uint)count);
						end = &arr[count - offset + 1];
					}
				}
				else
				{
					switch (range.[Friend]mEnd)
					{
					case .FromFront(let offset):
						Debug.Assert((uint)offset <= (uint)count);
						end = &arr[offset];
					case .FromEnd(let offset):
						Debug.Assert((uint)offset <= (uint)count);
						end = &arr[count - offset];
					}
				}

				return .(start, end - start);
			}
		}

		[Inline]
		public bool IsFull => count == Size;

		[Inline]
		public ref T First mut => ref this[0];

		[Inline]
		public ref T Last mut => ref this[count - 1];

		public void Clear() mut
		{
			arr = default;
			count = 0;
		}

		public void Add(T item) mut
		{
			Runtime.Assert(count < Size);

			arr[count++] = item;
		}

		public void AddRange(Span<T> items) mut
		{
			Runtime.Assert(count + items.Length <= Size);

			items.CopyTo(.(&arr[count], items.Length));
			count += items.Length;
		}

		public void Insert(int index, T item) mut
		{
			Runtime.Assert(index <= count);
			Runtime.Assert(count < Size);

			if (index < count)
				Internal.MemMove(&arr[index + 1], &arr[index], (count - index) * strideof(T), alignof(T));
			arr[index] = item;
			count++;
		}

		public bool Remove(T item) mut
		{
			bool found = false;
			for (let i < count)
			{
				if (found)
				{
					arr[i - 1] = arr[i];
				}
				else if (arr[i] == item)
					found = true;
			}
			if (found)
			{
				count--;
				arr[count] = default;
			}
			return found;
		}

		public void RemoveAt(int index) mut
		{
			Runtime.Assert((uint)index < (uint)count);
			if (index == count - 1)
			{
				arr[index] = default;
				count--;
				return;
			}
			Internal.MemMove(&arr[index], &arr[index + 1], (count - index - 1) * strideof(T), alignof(T));
		}

		public void RemoveAtFast(int index) mut
		{
			Runtime.Assert((uint)index < (uint)count);
			arr[index] = arr[--count];
		}

		public bool Contains(T item)
		{
			for (let i < count)
				if (arr[i] == item)
					return true;
			return false;
		}

		public void PopEnd() mut
		{
			Runtime.Assert(count > 0);
			arr[--count] = default;
		}

		public void PopStart() mut
		{
			[Inline]RemoveAt(0);
		}

		public Span<T>.Enumerator GetEnumerator()
		{
			return Span<T>(&arr[0], count).GetEnumerator();
		}
	}
}
