using System;
using System.Collections;
using System.Diagnostics;

namespace Dimtoo
{
	interface IComponentArrayBase
	{
		void ClearData();
		void OnEntityDestroyed(Entity e);

		bool GetSerializeData(Entity e, out Span<uint8> data);
		Span<uint8> ReserveData(Entity e);
	}

	class ComponentArray<T> : IComponentArrayBase where T : struct
	{
		Span<T> components;
		readonly Dictionary<Entity, int> entityToIndex ~ delete _;
		readonly List<Entity> indexToEntity ~ delete _;
		int count, capacity;

		[AllowAppend]
		public this(int capacity = MAX_ENTITIES)
		{
			let ptr = append T[capacity]*;
			components = .(ptr, capacity);
			this.capacity = capacity;

			let bookkeepingStartCap = (int32)Math.Min(capacity, 64);
			entityToIndex = new .(bookkeepingStartCap);
			indexToEntity = new .(bookkeepingStartCap);
		}

		public void ClearData()
		{
			Array.Clear(components.Ptr, components.Length);
			entityToIndex.Clear();
			indexToEntity.Clear();
			count = 0;
		}

		public void InsertData(Entity e, T component)
		{
			Debug.Assert(!entityToIndex.ContainsKey(e), "Component added to the same entity more than once");
			Debug.Assert(count < capacity, "No more space for components of this type");

			let newIndex = count++;
			components[newIndex] = component;

			// Add to lookups
			entityToIndex.Add(e, newIndex);
			if (indexToEntity.Count == newIndex)
				indexToEntity.Add(e);
			else indexToEntity[newIndex] = e;
		}

		public Span<uint8> ReserveData(Entity e)
		{
			Debug.Assert(!entityToIndex.ContainsKey(e), "Component added to the same entity more than once");
			Debug.Assert(count < capacity, "No more space for components of this type");

			let newIndex = count++;

			// Add to lookups
			entityToIndex.Add(e, newIndex);
			if (indexToEntity.Count == newIndex)
				indexToEntity.Add(e);
			else indexToEntity[newIndex] = e;

			return .((uint8*)&components[newIndex], sizeof(T));
		}

		public void RemoveData(Entity e)
		{
			Debug.Assert(entityToIndex.ContainsKey(e), "Component not present on this entity");

			let indexOfRemovedEntity = entityToIndex[e];
			let indexOfLastElement = --count;

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

		[Inline]
		public bool GetSerializeData(Entity e, out Span<uint8> componentData)
		{
			if (entityToIndex.TryGetValue(e, let index))
			{
				componentData = .((uint8*)&components[index], sizeof(T));
				return true;
			}
			componentData = .();
			return false;
		}
	}
}
