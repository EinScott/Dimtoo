using System;
using System.Collections;
using System.Diagnostics;
using Pile;

using internal Dimtoo;

namespace Dimtoo
{
	// @do pool components at some point?

	class Scene
	{
		EntityID next;

		List<List<ComponentBase>> componentsByType = new .();
		//List<List<ComponentBase>> activeComponentsByType = new .(); // @do hook up update loop & priority

		// Components keep a linked list to the other components. The component is the start of that list
		Dictionary<EntityID, ComponentBase> componentsByEntity = new .() ~ delete _;

		// @do not sure if this and update() is going to be here or in overrider?
		// probably here!
		List<ComponentBase> render;
		List<int> renderTypeStartIndeces; // (maybe layers instead) used to insert stuff later

		public this()
		{
			// Lists for all component types
			for (let i < ComponentBase.RealTypeByComponentType.Count)
				componentsByType.Add(new .());
		}

		public ~this()
		{
			for (let coll in componentsByType)
				DeleteContainerAndItems!(coll);

			delete componentsByType;
		}

		[Inline]
		internal bool Valid(Entity e) => e.ID < next && e.Scene == this;

		public Entity CreateEntity()
		{
			let ent = Entity(next++, this);
			OnCreateEntity(ent);
			return ent;
		}

		public Entity CreateEntityWith<T>() where T : ComponentBase, new
		{
			let ent = Entity(next++, this);
			OnCreateEntity(ent);
			CreateComponent(new T(), ent);

			return ent;
		}
		[Inline]
		public virtual void OnCreateEntity(Entity entity) {}

		public void DestroyEntity(Entity entity)
		{
			Debug.Assert(Valid(entity));

			if (componentsByEntity.TryGetValue(entity.ID, var itComp))
			{
				// Remove from dict
				componentsByEntity.Remove(entity.ID);

				// Destroy whole list
				while (itComp.nextOnEntity != null)
				{
					let component = itComp;
					itComp = itComp.nextOnEntity;

					DestroyComponent(component, false);
				}
			}
		}

		/// If the entity is valid and has any components on it
		mixin EntityInUse(Entity entity)
		{
			Debug.Assert(Valid(entity));
			if (!componentsByEntity.ContainsKey(entity.ID))
				return .Err(default);
		}

		[Inline]
		protected internal Result<ComponentBase> GetFirstComponentOnEntity(Entity entity)
		{
			EntityInUse!(entity);
			return componentsByEntity[entity.ID];
		}

		/// Component is expected to be a fresh, new .() one!
		protected internal void CreateComponent(ComponentBase component, Entity entity)
		{
			Debug.Assert(component.Entity == .Invalid);
			Debug.Assert(Valid(entity));

			// Register in lists
			Debug.Assert(component.Meta & .Registered > 0); // Component must be registered
			componentsByType[component.Type].Add(component);

			if (!componentsByEntity.ContainsKey(entity.ID))
				componentsByEntity.Add(entity.ID, component);
			else
			{
				// Append
				var itComp = componentsByEntity[entity.ID];
				while (itComp.nextOnEntity != null)
					itComp = itComp.nextOnEntity;

				itComp.nextOnEntity = component;
			}

			// Setup component
			component.Entity = entity;

			OnCreateComponent(component, entity);

			component.[Friend]Created();
		}
		[Inline]
		protected virtual void OnCreateComponent(ComponentBase component, Entity entity) {}

		protected internal void DestroyComponent(ComponentBase component, bool entityListClean = true)
		{
			Debug.Assert(Valid(component.Entity));

			component.[Friend]Destroyed();

			OnDestroyComponent(component);

			// Remove from lists
			Debug.Assert(component.Meta & .Registered > 0); // Component must be registered
			Debug.Assert(componentsByType[component.Type].Remove(component));

			if (entityListClean)
			{
				Debug.Assert(componentsByEntity.TryGetValue(component.Entity.ID, var itComp));
				bool lastComp = true;
				bool removed = false;
				while (itComp.nextOnEntity != null)
				{
					if (itComp.nextOnEntity == component)
					{
						let afterComp = itComp.nextOnEntity.nextOnEntity; // This might be null an that's fine

						// The next is out component, remove it from the list by referencing the thing after ours
						itComp.nextOnEntity = afterComp;

						removed = true;
						break;
					}

					lastComp = false;
					itComp = itComp.nextOnEntity;
				}
				Debug.Assert(removed);

				// Remove from dict if this was the only remaining component
				if (lastComp)
					componentsByEntity.Remove(component.Entity.ID);
			}

			// Delete component
			delete component;
		}
		[Inline]
		protected virtual void OnDestroyComponent(ComponentBase component) {}

		public struct ComponentEnumerator<T> : IEnumerator<T>, IResettable where T : ComponentBase
		{
			// @do This has the same problem that ids do not necessarily work well with inheritance

			ComponentBase current = null;
			Scene Scene;
			int Type;

			public this(Scene scene)
			{
				Scene = scene;
				let index = ComponentBase.RealTypeByComponentType.IndexOf(typeof(T));
				/*Debug.Assert(index >= 0, "C");*/
				Type = index;
			}

			public Result<T> GetNext() mut
			{
				if (Type < 0)
					return .Err; // Component type not registered

				//Scene.componentsByType[Type].GetEnumerator()

				return (T)current;
			}

			public void Reset() mut
			{
				current = null;
			}
		}

		// virtual void SortRenderOrder -- overrideable?
		// virtual functions for update and render order computations
	}
}
