using System;
using System.Collections;
using System.Diagnostics;
using Pile;
using Bon;

namespace Dimtoo
{
	// We want a distinction between empty/invalid entities and just, the 0th entity
	// with indices being unaffected. So all valid entities have the Mask bit on them
	// (and are thus serialized) A bit of a hack though..
	[BonTarget]
	struct Entity : IHashable
	{
		public const Entity Invalid = default;
		const uint16 Mask = 1 << 15;

		uint16 val;

#unwarn
		public static implicit operator uint16(Entity e) => (*((uint16*)&e) & ~Mask);
		public static implicit operator Entity(int i)
		{
			var b = (uint16)i | Mask;
			return *((Entity*)&b);
		}

		public override void ToString(String strBuffer)
		{
			(val & ~Mask).ToString(strBuffer);
		}

		public int GetHashCode()
		{
			return (val & ~Mask).GetHashCode();
		}
	}
	typealias ComponentType = uint8;

	static
	{
		public const uint16 MAX_ENTITIES = 4096;
		public const ComponentType MAX_COMPONENTS = 64;
	}

	class Scene
	{
		protected internal List<String> managedStrings = new .() ~ DeleteContainerAndItems!(_);

		protected readonly SystemManager sysMan = new .() ~ delete _;
		protected readonly ComponentManager compMan = new .() ~ delete _;
		protected readonly EntityManager entMan = new .() ~ delete _;

		protected readonly ComponentSerializer s = new .(this) ~ delete _;

		readonly List<Entity> deferEntityDestroy = new .() ~ delete _;

		public Camera2D camFocus;

		public void Clear()
		{
			entMan.ClearEntities();
			sysMan.ClearSystemEntities();
			compMan.ClearData();

			for (let s in managedStrings)
				delete s;
			managedStrings.Clear();
			deferEntityDestroy.Clear();
		}

		[Inline]
		public void SerializeScene(String buffer)
		{
			Debug.Assert(deferEntityDestroy.Count == 0);

			s.SerializeScene(buffer, true);
		}

		[Inline]
		public void SerializeSceneAsGroup(String buffer)
		{
			Debug.Assert(deferEntityDestroy.Count == 0);

			s.SerializeScene(buffer, false);
		}

		[Inline]
		public bool DeserializeScene(StringView saveString)
		{
			Clear();
			return s.Deserialize(saveString) case .Ok;
		}

		[Inline]
		public void SerializeGroup(Entity single, String buffer) => s.SerializeGroup(scope Entity[1](single), buffer, false);

		[Inline]
		public void SerializeGroup(String buffer, params Entity[] entities) => s.SerializeGroup(entities, buffer, false);

		[Inline]
		public bool CreateFromGroup(StringView saveString, List<Entity> createdEntities = null) => s.Deserialize(saveString, createdEntities) case .Ok;

		[Inline]
		public Entity CreateEntity() => entMan.CreateEntity();

		[Inline]
		public Result<void> CreateSpecificEntitiy(Entity e) => entMan.CreateSpecificEntity(e);

		public void DeferDestroyEntity(Entity e)
		{
			deferEntityDestroy.Add(e);
		}

		public void DoDeferredDestroyEntity()
		{
			for (let e in deferEntityDestroy)
				DestroyEntity(e);

			deferEntityDestroy.Clear();
		}

		public void DestroyEntity(Entity e)
		{
			Debug.Assert(entMan.EntityLives(e));

			entMan.DestroyEntity(e);
			compMan.OnEntityDestroyed(e);
			sysMan.OnEntityDestroyed(e);
		}

		[Inline]
		public bool EntityLives(Entity e) => entMan.EntityLives(e);

		[Inline]
		public HashSet<Entity>.Enumerator EnumerateEntities() => entMan.EnumerateEntities();

		[Inline]
		public void RegisterComponent<T>() where T : struct => compMan.RegisterComponent<T>();

		public void AddComponent<T>(Entity e, T component) where T : struct
		{
			Debug.Assert(entMan.EntityLives(e));
			compMan.AddComponent(e, component);

			var sig = entMan[e];
			sig.Add(compMan.GetComponentType<T>());
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);
		}

		public Span<uint8> ReserveComponent(Entity e, Type componentType)
		{
			Debug.Assert(entMan.EntityLives(e));
			let span = compMan.ReserveComponent(e, componentType);

			var sig = entMan[e];
			sig.Add(compMan.GetComponentType(componentType));
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);

			return span;
		}

		public void RemoveComponent<T>(Entity e) where T : struct
		{
			compMan.RemoveComponent<T>(e);

			var sig = entMan[e];
			sig.Remove(compMan.GetComponentType<T>());
			entMan[e] = sig;

			sysMan.OnEntitySignatureChanged(e, sig);

		}

		[Inline]
		public T* GetComponent<T>(Entity e) where T : struct => compMan.GetComponent<T>(e);

		[Inline]
		public bool GetComponentOptional<T>(Entity e, out T* component) where T : struct => compMan.GetComponentOptional<T>(e, out component);

		[Inline]
		public ComponentType GetComponentType<T>() where T : struct => compMan.GetComponentType<T>();

		[Inline]
		public T RegisterSystem<T>() where T : ComponentSystem
		{
			let sys = sysMan.RegisterSystem<T>();
			
			// Assemble signature from the system's requirements
			// Will error if the given types aren't already registered components
			Signature s = default;
			for (let t in sys.signatureTypes)
				s.Add(compMan.GetComponentType(t));
			sysMan.SetSignature<T>(s);

			sys.scene = this;
			return sys;
		}
	}
}
