using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	class ComponentManager
	{
		readonly Dictionary<Type, (ComponentType type, IComponentArrayBase array)> componentArrays = new .() ~ {
			for (let a in _)
				delete a.value.array;
			delete _;
		};
		ComponentType nextType;

		[Inline]
		public void RegisterComponent<T>() where T : struct
		{
			Debug.Assert(!componentArrays.ContainsKey(typeof(T)), "Component type already registered");

			componentArrays.Add(typeof(T), (nextType++, new ComponentArray<T>()));
		}

		[Inline]
		public ComponentType GetComponentType<T>() where T : struct
		{
			Debug.Assert(componentArrays.ContainsKey(typeof(T)), "Component type not registered");

			return componentArrays[typeof(T)].type;
		}

		[Inline]
		public ComponentType GetComponentType(Type t)
		{
			Debug.Assert(componentArrays.ContainsKey(t), "Component type not registered");

			return componentArrays[t].type;
		}

		[Inline]
		public void AddComponent<T>(Entity e, T component) where T : struct
		{
			GetComponentArray<T>().InsertData(e, component);
		}

		[Inline]
		public void RemoveComponent<T>(Entity e) where T : struct
		{
			GetComponentArray<T>().RemoveData(e);
		}

		[Inline]
		public T* GetComponent<T>(Entity e) where T : struct
		{
			return GetComponentArray<T>().GetData(e);
		}

		[Inline]
		/// For retrieving components that are not part of what the entities of a system require to qualify,
		/// but might be used by it if they are existant
		public bool GetComponentOptional<T>(Entity e, out T* component) where T : struct
		{
			component = GetComponentArray<T>().GetDataOrNull(e);
			return component != null;
		}

		[Inline]
		public void OnEntityDestroyed(Entity e)
		{
			// Notify all componentArrays
			for (let tup in componentArrays.Values)
				tup.array.OnEntityDestroyed(e);
		}

		[Inline]
		ComponentArray<T> GetComponentArray<T>() where T : struct
		{
			Debug.Assert(componentArrays.ContainsKey(typeof(T)), "Component type not registered");

			return (ComponentArray<T>)componentArrays[typeof(T)].array;
		}
	}
}
