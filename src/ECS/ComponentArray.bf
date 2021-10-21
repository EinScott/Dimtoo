using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	interface ComponentArrayBase
	{
		void OnEntityDestroyed(Entity e);
	}

	class ComponentArray<T> : ComponentArrayBase where T : struct
	{
		T[MAX_ENTITIES] components;
		readonly Dictionary<Entity, int> entityToIndex = new .() ~ delete _;
		readonly List<Entity> indexToEntity = new .() ~ delete _;
		int size;

		public void InsertData(Entity e, T component)
		{
			Debug.Assert(!entityToIndex.ContainsKey(e), "Component added to the same entity more than once");

			let newIndex = size++;
			components[e] = component;

			// Add to lookups
			entityToIndex.Add(e, newIndex);
			if (indexToEntity.Count == newIndex)
				indexToEntity.Add(e);
			else indexToEntity[newIndex] = e;
		}

		public void RemoveData(Entity e)
		{
			Debug.Assert(entityToIndex.ContainsKey(e), "Component not present on this entity");

			let indexOfRemovedEntity = entityToIndex[e];
			let indexOfLastElement = --size;

			// Replace removed with last element
			components[indexOfRemovedEntity] = components[indexOfLastElement];

			// Update index of moved last element
			Entity entityOfLastElement = indexToEntity[indexOfLastElement];
			entityToIndex[entityOfLastElement] = indexOfRemovedEntity;
			indexToEntity[indexOfRemovedEntity] = entityOfLastElement;

			// Clean up lookup of removed
			entityToIndex.Remove(e);
			indexToEntity.PopBack();
		}

		[Inline]
		public T* GetData(Entity e)
		{
			Debug.Assert(entityToIndex.ContainsKey(e), "Component not present on this entity");

			return &components[entityToIndex[e]];
		}

		[Inline]
		public T* GetDataOrNull(Entity e)
		{
			let exists = entityToIndex.TryGetValue(e, let index);
			return exists ? &components[index] : null;
		}

		[Inline]
		public void OnEntityDestroyed(Entity e)
		{
			// If the entity had that component, remove it from us
			if (entityToIndex.ContainsKey(e))
				RemoveData(e);
		}
	}
}
