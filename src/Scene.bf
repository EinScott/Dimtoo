using System;
using System.Collections;
using System.Diagnostics;
using Pile;

using internal Dimtoo;

namespace Dimtoo
{
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct UpdateAttribute : Attribute {}
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct RenderAttribute : Attribute {}
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct PriorityAttribute : Attribute, this(int updatePriority);
	[AttributeUsage(.Class, .ReflectAttribute|.DisallowAllowMultiple)]
	struct EntityLimitedAttribute : Attribute {}
	/*[AttributeUsage(.Class)]
	struct RequireAttribute<T> : Attribute where T : ComponentBase
	{
		public const Type Required = typeof(T);
	}*/

	class Scene
	{
		public abstract class System
		{
			// For things acting on multiple components/entities, like collision, which is not really owned by a system
			// these should get callbacks for all the common actions
			// but also, these are characteristically not really accessed by the outside

			// or just scene-level extensions
		}

		// IF we had multidicts, most of this (and assets) could be simpler

		uint32 next = 1;
		Dictionary<Type, List<Component>> componentsByType = new .();
		internal Dictionary<uint32, Component> componentsByEntity = new .() ~ delete _; // ComponentBase has linked list

		// render by layer...?

		public ~this()
		{
			for (let list in componentsByType.Values)
			{
				for (var value in list)
					delete value;
				delete list;
			}	

			delete componentsByType;
		}

		// get entities by tag, get components by attribute, get components by type, get components by entity
		// components are allocated and deleted only by this thing!
		// do get()s lookups respect inheritance? because they probably should

		// enable disable on entity and component layer
		// so does every component need two enalbed flags then? i guess so... yeah, just a bit field?

		public void Update()
		{
			// to change: active

			for (let type in Component.updateParticipants)
			{
				if (componentsByType.TryGetValue(type, let list))
				{
					for (let comp in list)
						comp.[Friend]Update();
				}
			}
		}

		public void Render(Batch2D batch)
		{
			// to change: layers?? i guess...
			// so we have batcher layers and actual layers... what diff does it make?

			for (let type in Component.renderParticipants)
			{
				if (componentsByType.TryGetValue(type, let list))
				{
					for (let comp in list)
						comp.[Friend]Render(batch);
				}
			}
		}

		[Inline]
		bool Valid(Entity e) => e.ID != 0 && e.Scene == this && e.ID < next;
		[Inline]
		bool InUse(Entity e) => Valid(e) && componentsByEntity.ContainsKey(e);

		public Entity CreateEntity()
		{
			let ent = Entity(next++, this);
			OnCreateEntity(ent);
			return ent;
		}
		public Entity CreateEntityWith<T>(T component) where T : Component, new
		{
			let ent = Entity(next++, this);
			OnCreateEntity(ent);
			CreateComponent<T>(component, ent);

			return ent;
		}
		[Inline]
		protected virtual void OnCreateEntity(Entity e) {}

		public void DestroyEntity(Entity e)
		{
			Runtime.Assert(InUse(e));

			if (componentsByEntity.TryGetValue(e, var itComp))
			{
				// Destroy all components
				while (itComp.nextOnEntity != null)
				{
					let comp = itComp;
					itComp = itComp.nextOnEntity;

					DestroyComponent(comp, false);
				}

				// Remove whole entry
				componentsByEntity.Remove(e);
			}
		}

		protected internal T CreateComponent<T>(T component, Entity e) where T : Component
		{
			Runtime.Assert(!(Component.entityLimitedComponents.Contains(typeof(T)) && e.GetComponent<T>() case .Ok), "Component can only be on entity once");
			Runtime.Assert(Valid(e), "Invalid entity");
			Runtime.Assert(component.Entity.Scene == null, "Component already in use");

			component.Entity = e;

			if (!componentsByType.ContainsKey(typeof(T)))
				componentsByType.Add(typeof(T), new .());
			componentsByType[typeof(T)].Add(component);

			if (!componentsByEntity.ContainsKey(e))
				componentsByEntity.Add(e, component);
			else
			{
				// Append to linked list
				var itComp = componentsByEntity[e];
				while (itComp.nextOnEntity != null)
					itComp = itComp.nextOnEntity;

				itComp.nextOnEntity = component;
			}

			OnCreateComponent(component, e);

			component.[Friend]Attach();
			return component;
		}
		[Inline]
		protected virtual void OnCreateComponent(Component component, Entity e) {}

		protected internal void DestroyComponent(Component component, bool maintainEntityList = true, bool deleteComp = true)
		{
			Runtime.Assert(InUse(component.Entity));

			OnDestroyComponent(component);

			componentsByType[component.GetType()].Remove(component);

			if (maintainEntityList)
			{
				Runtime.Assert(componentsByEntity.TryGetValue(component.Entity, var itComp));

				if (itComp.nextOnEntity == null)
					componentsByEntity.Remove(component.Entity);
				else
				{
					bool removed = false;
					while (itComp.nextOnEntity != null)
					{
						if (itComp.nextOnEntity == component)
						{
							itComp.nextOnEntity = itComp.nextOnEntity.nextOnEntity; // This might be null and that's fine

							removed = true;
							break;
						}

						itComp = itComp.nextOnEntity;
					}
					Runtime.Assert(removed);
				}
			}

			if (deleteComp)
				delete component;
		}
		[Inline]
		protected virtual void OnDestroyComponent(Component component) {}
	}
}
