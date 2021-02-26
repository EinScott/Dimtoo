using System;
using System.Collections;

using internal Dimtoo;

namespace Dimtoo
{
	typealias EntityID = uint32;

	struct Entity
	{
		public static readonly Entity Invalid = .(0, null);
		// @do enabled on components as well as SetEnabled here, which sets another
		// also needs to notify scene

		public readonly EntityID ID;
		public readonly Scene Scene;

		internal this(EntityID id, Scene scene)
		{
			ID = id;
			Scene = scene;
		}

		[Inline]
		public void Destroy() => Scene.DestroyEntity(this);

		[Inline]
		public T CreateComponent<T>() where T : ComponentBase, new
		{
			return Scene.CreateComponent(.. new T(), this);
		}

		[Inline]
		public void DestroyComponent(ComponentBase component)
		{
			Scene.DestroyComponent(component);
		}

		public Result<T> GetComponent<T>() where T : ComponentBase
		{
			ComponentBase current = Try!(Scene.GetFirstComponentOnEntity(this));

			// Iterate until current is of requested type
			while (!current is T)
			{
				if (current.nextOnEntity == null)
					return .Err;

				current = current.nextOnEntity;
			}

			return (T)current;
		}

		public void GetComponents<T>(List<T> into) where T : ComponentBase
		{
			for (let comp in EnumerateComponents<T>())
				into.Add(comp);
		}

		public void GetComponents<T>(Span<T> into) where T : ComponentBase
		{
			int slot = 0;
			for (let comp in EnumerateComponents<T>())
			{
				if (slot >= into.Length)
					break;

				into[slot++] = comp;
			}
		}

		[Inline]
		public ComponentEnumerator<T> EnumerateComponents<T>() where T : ComponentBase
		{
			return .(this);
		}

		public struct ComponentEnumerator<T> : IEnumerator<T>, IResettable where T : ComponentBase
		{
			Entity Entity;
			ComponentBase current = null;

			public this(Entity entity)
			{
				Entity = entity;
			}

			public Result<T> GetNext() mut
			{
				if (current == null)
				{
					// Set first, will return err if entity doesn't have any components
					current = Try!(Entity.Scene.GetFirstComponentOnEntity(Entity));
				}
				else if (current.nextOnEntity != null)
				{
					// Set next
					current = current.nextOnEntity;
				}
				else return .Err;

				// Iterate until current is of requested type
				//Type currentType = current.GetType();

				//while (currentType != typeof(T) || !currentType.IsSubtypeOf(typeof(T)))
				while (!current is T)
				{
					if (current.nextOnEntity == null)
						return .Err;

					current = current.nextOnEntity;
					//currentType = current.GetType();
				}

				return (T)current;
			}

			public void Reset() mut
			{
				current = null;
			}
		}

		[Commutable]
		public static bool operator==(Entity a, Entity b) => a.ID == b.ID && a.Scene == b.Scene;
	}
}
