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

		public void Clear()
		{
			entMan.ClearEntities();
			sysMan.ClearSystemEntities();
			compMan.ClearData();

			for (let s in managedStrings)
				delete s;
			managedStrings.Clear();
		}

		[Inline]
		public void SerializeScene(String buffer, bool includeDefault = false) => s.SerializeScene(buffer, true, includeDefault);

		[Inline]
		public void SerializeSceneAsGroup(String buffer, bool includeDefault = false) => s.SerializeScene(buffer, false, includeDefault);

		[Inline]
		public bool DeserializeScene(StringView saveString)
		{
			Clear();
			return s.Deserialize(saveString) case .Ok;
		}

		[Inline]
		public void SerializeGroup(Entity single, String buffer, bool includeDefault = false) => s.SerializeGroup(scope Entity[1](single), buffer, false, includeDefault);

		[Inline]
		public void SerializeGroup(String buffer, params Entity[] entities) => s.SerializeGroup(entities, buffer, false, false);

		[Inline]
		public void SerializeGroup(String buffer, bool includeDefault, params Entity[] entities) => s.SerializeGroup(entities, buffer, false, includeDefault);

		[Inline]
		public bool CreateFromGroup(StringView saveString, List<Entity> createdEntities = null) => s.Deserialize(saveString, createdEntities) case .Ok;

		[Inline]
		public Entity CreateEntity() => entMan.CreateEntity();

		[Inline]
		public Result<void> CreateSpecificEntitiy(Entity e) => entMan.CreateSpecificEntity(e);

		public void DestroyEntity(Entity e)
		{
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

			sys.componentManager = compMan;
			return sys;
		}
	}
}
