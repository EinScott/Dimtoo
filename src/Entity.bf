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

		public T GetComponent<T>() where T : ComponentBase
		{
			return null;
		}

		public void GetComponents<T>(List<T> into) where T : ComponentBase
		{

		}

		public void GetComponents<T>(Span<T> into) where T : ComponentBase
		{

		}

		[Inline]
		public ComponentEnumerator<T> EnumerateComponents<T>() where T : ComponentBase
		{
			return .(this);
		}	

		public struct ComponentEnumerator<T> : IEnumerator<T>, IResettable where T : ComponentBase
		{
			Entity Entity;
			T current = null;

			public this(Entity entity)
			{
				Entity = entity;
			}

			public Result<T> GetNext() mut
			{
				// @do lookup id for typeof t, then look if the component looked at has that TypeID
				// to see if we can (unsafe cast) it to T
				// the function for finding the first of type T in that list should be separate, since
				// GetComponent(s) etc also needs the same thing
				/*if (current == null)
				{
					// Set first
					current = 
				}
				else if (current.nextOnEntity != null)
				{
					// Set next
					//current = current.nextOnEntity;
				}
				else return .Err;*/

				return current;
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
