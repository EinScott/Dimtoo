using System;
using System.Collections;
using System.Diagnostics;

using internal Dimtoo;

namespace Dimtoo
{
	struct Entity : IEnumerable<Component>
	{
		internal readonly uint32 ID;
		internal readonly Scene Scene;

		internal this(uint32 id, Scene scene)
		{
			ID = id;
			Scene = scene;
		}

		[Inline]
		public void Destroy() => Scene.DestroyEntity(this);

		[Inline]
		public T CreateComponent<T>() where T : Component, new
		{
			return Scene.CreateComponent<T>(this);
		}

		[Inline]
		public void DestroyComponent(Component component)
		{
#if DEBUG
			bool contained = false;
			for (let comp in this)
				if (comp == component)
				{
					contained = true;
					break;
				}

			if (!contained)
				Debug.FatalError("Destroying component on entity that doesn't own it");
#endif

			Scene.DestroyComponent(component);
		}

		// get components

		public Result<T> GetComponent<T>() where T : Component
		{
			return ComponentEnumerator<T>(this).GetNext();
		}

		[Inline]
		public ComponentEnumerator<T> GetTEnumerator<T>() where T : Component
		{
			return .(this);
		}

		[Inline]
		public ComponentEnumerator GetEnumerator() => .(this);

		public struct ComponentEnumerator : IEnumerator<Component>, IResettable
		{
			Entity entity;
			Component current = null;

			public this(Entity e)
			{
				entity = e;
			}

			public Result<Component> GetNext() mut
			{
				if (current != null)
				{
					if (current.nextOnEntity != null) // Next in list
						current = current.nextOnEntity;
					else return .Err; // End of list
				}
				else // Start of potential list
				{
					if (!entity.Scene.componentsByEntity.TryGetValue(entity, out current))
						return .Err;
				}

				return current;
			}

			public void Reset() mut
			{
				current = null;
			}
		}

		public struct ComponentEnumerator<T> : IEnumerator<T>, IResettable where T : Component
		{
			Entity entity;
			T current = null;

			public this(Entity e)
			{
				entity = e;
			}

			[Inline]
			public T Current => current;

			public Result<T> GetNext() mut
			{
				Component it = current;

				if (it != null)
				{
					if (it.nextOnEntity != null) // Next in list
						it = it.nextOnEntity;
					else return .Err; // End of list
				}
				else // Start of potential list
				{
					if (!entity.Scene.componentsByEntity.TryGetValue(entity, out it))
						return .Err;
				}

				while (!(it is T))
				{
					if (it.nextOnEntity == null)
						return .Err;

					it = it.nextOnEntity;
				}

				return current = (T)it;
			}

			public void Reset() mut
			{
				current = null;
			}
		}

		[Inline]
		public static implicit operator uint32(Entity e) => e.ID;
		[Commutable]
		public static bool operator==(Entity a, Entity b) => a.ID == b.ID && a.Scene === b.Scene;
	}
}
