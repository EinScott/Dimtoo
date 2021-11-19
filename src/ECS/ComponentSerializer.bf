using System;
using System.IO;
using System.Collections;
using System.Diagnostics;
using Pile;
using System.Reflection;

namespace Dimtoo
{
	// TODO: do deserialize / create entity from string
	// do full scene serialize / deserialize

	// NOSERIALIZE attribute?
	// CUSTOMSERIALIZE attribute? -> call some function to fill in the type fully after the base deserialize! -> for things that need assets?

	[AttributeUsage(.Struct|.Enum, .AlwaysIncludeTarget | .ReflectAttribute, ReflectUser = .AllMembers, AlwaysIncludeUser = .IncludeAllMethods | .AssumeInstantiated)]
	struct SerializableAttribute : Attribute, IComptimeTypeApply
	{
		[Comptime]
		public void ApplyToType(Type type)
		{
			// @report when typing that string, there were lots of crashes
			let name = type.GetName(.. scope .());
			Compiler.EmitTypeBody(type, scope $"""
				static this
				{{
					if (!ComponentSerializer.componentTypes.ContainsKey("{name}"))
						ComponentSerializer.componentTypes.Add("{name}", typeof(Self));
				}}
				""");
		}
	}

	class ComponentSerializer
	{
		public static Dictionary<String, Type> componentTypes = new .() ~ delete _;

		ComponentManager compMan;

		public this(ComponentManager comp)
		{
			compMan = comp;
		}

		static mixin VariantDataIsZero(Variant val)
		{
			bool isZero = true;
			for (var i < val.VariantType.Size)
				if (*(uint8*)val.DataPtr != 0)
					isZero = false;
			isZero
		}

		static mixin RemoveTrailingComma(String buffer)
		{
			if (buffer.EndsWith(",\n"))
				buffer.RemoveFromEnd(2);
		}

		public void GetSerializeString(Scene scene, String buffer, bool exactEntity = true, bool includeDefault = false)
		{
			buffer.Append("[\n");

			for (let entity in scene.[Friend]entMan.EnumerateEntities())
			{
				GetSerializeString(entity, buffer, exactEntity, includeDefault);
				buffer.Append(",\n");
			}

			RemoveTrailingComma!(buffer);

			buffer.Append("\n]");
		}

		public void GetSerializeString(Entity e, String buffer, bool exactEntity = true, bool includeDefault = false)
		{
			if (exactEntity)
				buffer.Append(scope $"{e}: [\n");
			else buffer.Append("[\n");

			for (let entry in compMan.[Friend]componentArrays)
				if (entry.value.array.GetSerializeData(e, let data))
					if (SerializeStruct(entry.key, Variant.CreateReference(entry.key, data), buffer, includeDefault))
						buffer.Append(",\n");

			RemoveTrailingComma!(buffer);

			buffer.Append("\n]");
		}

		bool SerializeStruct(Type structType, Variant structVal, String buffer, bool includeDefault)
		{
			var structVal;
			Debug.Assert(structType.IsStruct);

			if (!structType.HasCustomAttribute<SerializableAttribute>())
			{
				//Log.Debug(scope $"Struct {structType} is not marked as [Serializable] and will not be included");
				return false;
			}

			structType.GetName(buffer);
			buffer.Append("{\n");

			for (let m in structType.GetFields(.Public|.Instance))
			{
				if ((m.FieldType.IsEnum && m.FieldType.IsUnion) || m.FieldType.IsPointer || m.FieldType.IsObject && !m.FieldType is SizedArrayType)
					continue;

				Variant val = Variant.CreateReference(m.FieldType, ((uint8*)structVal.DataPtr) + m.MemberOffset);

				if (VariantDataIsZero!(val))
					continue;

				let oldLen = buffer.Length;
				buffer.Append(m.Name);
				buffer.Append("=");

				let mention = SerializeValue(ref val, buffer, includeDefault);

				if (!mention)
				{
					// Revert to previous state, just don't mention this field!
					buffer.RemoveFromEnd(buffer.Length - oldLen);
					continue;
				}

				buffer.Append(",\n");
			}

			RemoveTrailingComma!(buffer);

			if (!buffer.EndsWith("{\n"))
				buffer.Append("\n}");
			else
			{
				// Do <Name>{} on empty stuff
				buffer.RemoveFromEnd(1);
				buffer.Append('}');
			}

			return true;
		}

		bool SerializeValue(ref Variant val, String buffer, bool includeDefault)
		{
			Type fieldType = val.VariantType;

			if (fieldType.IsPointer || fieldType.IsObject && !fieldType is SizedArrayType)
				return false; // Don't serialize objects or pointers
			else if (fieldType.IsInteger)
			{
				switch (fieldType)
				{
				case typeof(int8), typeof(int16), typeof(int32), typeof(int64), typeof(int):
					int64 integer = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&integer, sizeof(int64)));
					integer.ToString(buffer);
				default: // unsigned
					uint64 integer = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&integer, sizeof(uint64)));
					integer.ToString(buffer);
				}
			}
			else if (fieldType.IsFloatingPoint)
			{
				switch (fieldType)
				{
				case typeof(float):
					let f = val.Get<float>();
					f.ToString(buffer);
				case typeof(double):
					let d = val.Get<double>();
					d.ToString(buffer);
				default: Debug.FatalError();
				}
			}
			else if (fieldType == typeof(bool))
			{
				val.Get<bool>().ToString(buffer);
			}
			else if (fieldType is SizedArrayType)
			{
				buffer.Append("[\n");

				let t = (SizedArrayType)fieldType;
				let count = t.ElementCount;
				let arrType = t.UnderlyingType;

				var zeroIndex = 0, cutBufferLen = buffer.Length;
				var ptr = (uint8*)val.DataPtr;
				for (let i < count)
				{
					var arrVal = Variant.CreateReference(arrType, ptr);

					if (SerializeValue(ref arrVal, buffer, includeDefault))
					{
						if (!arrType.IsPrimitive)
							buffer.Append(",\n");
						else buffer.Append(", "); // Just put primitives in one line!
					}
					else return false; // Just don't serialize the array at all!

					if (!VariantDataIsZero!(arrVal))
					{
						zeroIndex = i + 1; // Next one might be
						cutBufferLen = buffer.Length; // In that case, cut here
					}

					ptr += arrType.Size;
				}

				// Cut the array when all thats left is default
				if (zeroIndex < count)
					buffer.RemoveFromEnd(buffer.Length - cutBufferLen);

				if (buffer[buffer.Length - 2] == ',')
					buffer.RemoveFromEnd(2); // Remove last ", " or ",\n"

				buffer.Append("\n]");
			}
			else if (fieldType.IsEnum)
			{
				if (fieldType.IsUnion)
				{
					Log.Debug("Cannot serialize union enum");
				}
				else
				{
					int64 value = 0;
					Span<uint8>((uint8*)val.DataPtr, fieldType.Size).CopyTo(Span<uint8>((uint8*)&value, sizeof(int64)));
					Enum.EnumToString(fieldType, buffer, value);
				}
			}
			else if (fieldType.IsStruct)
			{
				var structType = fieldType;

				// Fake reflection info for pile types
				switch (fieldType)
				{
				case typeof(Pile.Rect):
					val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(Rect)) & ~3) + (val.[Friend]mStructType & 3);
					structType = typeof(Rect);
				case typeof(Pile.Vector2):
					val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(Vector2)) & ~3) + (val.[Friend]mStructType & 3);
					structType = typeof(Vector2);
				case typeof(Pile.Point2):
					val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(Point2)) & ~3) + + (val.[Friend]mStructType & 3);
					structType = typeof(Point2);
				case typeof(Pile.UPoint2):
					val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(UPoint2)) & ~3) + + (val.[Friend]mStructType & 3);
					structType = typeof(UPoint2);
				}

				return SerializeStruct(structType, val, buffer, includeDefault);
			}
			else
			{
				Log.Debug($"Couldn't serialize field: {fieldType.GetName(.. scope .())}");
				return false;
			}

			return true;
		}

		static mixin ForceEat(char8 expect, ref StringView buffer)
		{
			if (buffer.StartsWith(expect))
				buffer.RemoveFromStart(1);
			else return .Err(default);
		}

		static mixin EatSpace(ref StringView buffer)
		{
			var i = 0;
			for (; i < buffer.Length; i++)
			{
				if (!buffer[i].IsWhiteSpace)
					break;
			}

			buffer.RemoveFromStart(i);
		}

		public Result<void> DeserializeFromString(Scene scene, StringView buffer)
		{
			var buffer;
			EatSpace!(ref buffer);

			ForceEat!('[', ref buffer);

			EatSpace!(ref buffer);

			while ({
				EatSpace!(ref buffer);
				buffer[0] != ']'
				})
			{
				if (DeserializeEntityFromString(scene, ref buffer) case .Err)
					return .Err; // Entity deserialize failure

				EatSpace!(ref buffer);

				if (buffer[0] == ',')
					buffer.RemoveFromStart(1);
			}

			ForceEat!(']', ref buffer);

			return .Ok;
		}

		public Result<void> DeserializeEntityFromString(Scene scene, ref StringView buffer)
		{
			EatSpace!(ref buffer);

			Entity e;
			if (buffer[0].IsNumber)
			{
				var numLen = 1;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber)
					numLen++;

				if (uint.Parse(.(&buffer[0], numLen)) case .Ok(let val))
				{
					e = (uint16)val;
					if (e >= MAX_ENTITIES)
						return .Err; // Entity out of range

					buffer.RemoveFromStart(numLen);
				}
				else return .Err; // Parsing failure

				if (scene.CreateSpecificEntitiy(e) case .Err)
					return .Err; // Entity already exists

				EatSpace!(ref buffer);
				ForceEat!(':', ref buffer);
				EatSpace!(ref buffer);
			}
			else
			{
				// Just take any available entity
				e = scene.CreateEntity();
			}

			ForceEat!('[', ref buffer);

			while ({
				EatSpace!(ref buffer);
				buffer[0] != ']'
				})
			{
				// Get type from name
				if (DeserializeStructType(let structType, ref buffer) case .Err)
					return .Err; // Type error

				// TODO
				// also need way to access component/scene stuff through Type + Span or something?
				// scene.AddComponent(e, component.VariantType, .(component.DataPtr, component.VariantType.Size));
				// This function should probably do lots of internal asserts!
				var structMemory = Span<uint8>();

				// Fill in type from body
				if (DeserializeStructBody(structType, structMemory, ref buffer) case .Err)
					return .Err; // Deserialize error

				EatSpace!(ref buffer);

				if (buffer[0] == ',')
					buffer.RemoveFromStart(1);
			}

			ForceEat!(']', ref buffer);

			return .Ok;
		}

		Result<void> DeserializeStructType(out Type structType, ref StringView buffer)
		{
			EatSpace!(ref buffer);

			{
				var nameLen = 0;
				for (; nameLen < buffer.Length; nameLen++)
					if (!buffer[nameLen].IsLetterOrDigit)
						break;

				let name = buffer.Substring(0, nameLen);
				buffer.RemoveFromStart(nameLen);

				if (!componentTypes.TryGetValue(scope String(name), out structType))
					return .Err; // Type not recognized
			}

			Debug.Assert(structType != null);

			return .Ok;
		}

		Result<void> DeserializeStructBody(Type structType, Span<uint8> structTargetMem, ref StringView buffer)
		{
			EatSpace!(ref buffer);
			ForceEat!('{', ref buffer);

			if (structTargetMem.Length != structType.Size)
				return .Err; // Size miss-match!

			Variant structVal = Variant.CreateReference(structType, structTargetMem.Ptr);

			while ({
				EatSpace!(ref buffer);
				buffer[0] != '}'
				})
			{
				// Get field name
				var nameLen = 0;
				for (; nameLen < buffer.Length; nameLen++)
					if (!buffer[nameLen].IsLetterOrDigit)
						break;

				let name = buffer.Substring(0, nameLen);
				buffer.RemoveFromStart(nameLen);

				EatSpace!(ref buffer);
				ForceEat!('=', ref buffer);
				EatSpace!(ref buffer);

				FieldInfo fieldInfo;
				switch (structType.GetField(scope .(name)))
				{
				case .Ok(let val):
					fieldInfo = val;
				case .Err:
					continue; // Field does not exist
				}

				Variant fieldVal = Variant.CreateReference(fieldInfo.FieldType, ((uint8*)structVal.DataPtr) + fieldInfo.MemberOffset);

				if (DeserializeValue(ref fieldVal, ref buffer) case .Err)
					return .Err; // Field deserialize error

				EatSpace!(ref buffer);

				if (buffer[0] == ',')
					buffer.RemoveFromStart(1);
			}

			ForceEat!('}', ref buffer);

			return .Ok;
		}

		Result<void> DeserializeValue(ref Variant val, ref StringView buffer)
		{
			Type fieldType = val.VariantType;

			if (fieldType.IsInteger)
			{
				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '-')
					numLen++;

				if (numLen == 0)
					return .Err; // No number there

				switch (fieldType)
				{
				case typeof(int8), typeof(int16), typeof(int32), typeof(int64), typeof(int):
					if (int64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
						Internal.MemCpy(val.DataPtr, &num, fieldType.Size);
					else return .Err; // Number parsing error
				default: // unsigned
					if (uint64.Parse(.(&buffer[0], numLen)) case .Ok(var num))
						Internal.MemCpy(val.DataPtr, &num, fieldType.Size);
					else return .Err; // Number parsing error
				}
			}
			else if (fieldType.IsFloatingPoint)
			{
				var numLen = 0;
				while (buffer.Length > numLen + 1 && buffer[numLen].IsNumber || buffer[numLen] == '.' || buffer[numLen] == '-')
					numLen++;

				if (numLen == 0)
					return .Err; // No number there

				switch (fieldType)
				{
				case typeof(float):
					if (float.Parse(.(&buffer[0], numLen)) case .Ok(let num))
						*(float*)val.DataPtr = num;
				case typeof(double):
					if (double.Parse(.(&buffer[0], numLen)) case .Ok(let num))
						*(double*)val.DataPtr = num;
				default:
					return .Err; // Invalid floating point
				}
			}
			else if (fieldType == typeof(bool))
			{
				if (buffer.StartsWith(bool.TrueString, .OrdinalIgnoreCase))
					*(bool*)val.DataPtr = true;
				else if (buffer.StartsWith(bool.FalseString, .OrdinalIgnoreCase))
					NOP!(); // Is already 0, sooOOo nothing to do here
				else return .Err; // Invalid bool
			}
			else if (fieldType is SizedArrayType)
			{
				ForceEat!('[', ref buffer);
				EatSpace!(ref buffer);

				while ({
					EatSpace!(ref buffer);
					buffer[0] != ']'
					})
				{
					// TODO: element parse! (call this)

					EatSpace!(ref buffer);

					if (buffer[0] == ',')
						buffer.RemoveFromStart(1);
				}
	
				ForceEat!(']', ref buffer);
			}
			else if (fieldType.IsEnum)
			{
				// TODO: accept numbers, but since we have the enum type we can also accept names
			}
			else if (fieldType.IsStruct)
			{
				// TODO: Call struct thing. Mind the conversion of type -> Pile.Point2 to Point2 and so on... maybe unify that function of Type conversion!
			}
			else return .Err; // Unknown type

			return .Ok;
		}

		// FAKE PILE TYPES WITH REFLECTION INFO

		[Serializable]
		struct Rect
		{
			public int X;
			public int Y;
			public int Width;
			public int Height;
		}

		[Serializable]
		struct Vector2
		{
			public float X, Y;
		}

		[Serializable]
		struct Point2
		{
			public int X, Y;
		}

		[Serializable]
		struct UPoint2
		{
			public uint X, Y;
		}
	}
}
