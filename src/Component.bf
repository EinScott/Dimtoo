using System;
using System.Reflection;
using System.Collections;
using System.Diagnostics;
using Pile;

using internal Dimtoo;

namespace Dimtoo
{
	// Static meta data
	enum ComponentMeta : uint8
	{
		None = 0,
		Registered = 1,
		Update = _ << 1,
		Render = _ << 1
	}

	// @do incorporate update priority!
	[AttributeUsage(.Class,.DisallowAllowMultiple|.NotInherited,ReflectUser=.None)]
	struct RegisterComponentAttribute : Attribute, IComptimeTypeApply
	{
		[Comptime]
		public void ApplyToType(Type type)
		{
			if(!type.IsSubtypeOf(typeof(ComponentBase)))
				Runtime.FatalError("Components must inherit from Component<T> where T is the inheritor");

			// Compute meta
			ComponentMeta meta = .Registered;
			for (let t in type.Interfaces)
			{
				if ((Type)t == typeof(IUpdate))
					meta |= .Update;

				if ((Type)t == typeof(IRender))
					meta |= .Render;
			}

			Compiler.EmitTypeBody(type, scope $"""
				static this
				{{
					Self.[Friend]meta = (ComponentMeta){meta.Underlying};
				}}
				""");
		}
	}

	typealias ComponentType = uint32;

	abstract class ComponentBase
	{
		// ComponentType is the index to the Type that registered it
		internal static List<Type> RealTypeByComponentType = new List<Type>() ~ delete _;

		internal static ComponentType RegisterComponentType(Type type)
		{
			if (RealTypeByComponentType.Contains(type))
				Runtime.FatalError("Every component type can only be registered once");

			RealTypeByComponentType.Add(type);
			return (ComponentType)RealTypeByComponentType.Count - 1;
		}

		internal ComponentBase nextOnEntity;

		public abstract ComponentMeta Meta { get; }
		public abstract ComponentType Type { get; }

		public Entity Entity { get; internal set; }

		protected virtual void Created() {}
		protected virtual void Destroyed() {}
	}

	class Component<T> : ComponentBase where T : ComponentBase, new
	{
		static readonly ComponentMeta meta;
		static readonly ComponentType type = RegisterComponentType(typeof(Self));

		public override ComponentType Type => type;
		public override ComponentMeta Meta => meta;
	}

	interface IUpdate
	{
		public void Update();
	}

	interface IRender
	{
		public void Render();
	}	
}
