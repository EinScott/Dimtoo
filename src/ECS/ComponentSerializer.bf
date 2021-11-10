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

	[AttributeUsage(.Struct|.Enum, .AlwaysIncludeTarget | .ReflectAttribute, ReflectUser = .AllMembers, AlwaysIncludeUser = .IncludeAllMethods | .AssumeInstantiated)]
	struct SerializableAttribute : Attribute
	{

	}

	class ComponentSerializer
	{
		ComponentManager compMan;

		public this(ComponentManager comp)
		{
			compMan = comp;
		}

		public void GetSerializeString(Entity e, String buffer)
		{
			buffer.Append("[\n");

			for (let entry in compMan.[Friend]componentArrays)
				if (entry.value.array.GetSerializeData(e, let data))
					if (Serialize(entry.key, Variant.CreateReference(entry.key, data), buffer))
						buffer.Append(",\n");

			buffer.Append("]");
		}

		// TODO: explicit option to include everything, otherwise just include
		// non zero stuff? we'll set the structs to default when loading anyway, so 0
		// isnt of much significance as a value

		bool Serialize(Type type, Variant component, String buffer)
		{
			if (!type.HasCustomAttribute<SerializableAttribute>())
				return false;

			type.GetName(buffer);
			buffer.Append("{\n");

			for (let m in type.GetFields(.Public|.Instance))
			{
				if (m.FieldType.IsEnum && m.FieldType.IsUnion)
					continue;

				Variant val;
				if (m.GetValue(component) case .Ok(let value))
					val = value;
				else
				{
					Log.Debug($"Failed to get value of field {m.Name}, which is a {m.FieldType.GetName(.. scope .())}");
					continue;
				}

				buffer.Append(m.Name);
				buffer.Append("=");

				if (m.FieldType.IsInteger)
				{
					switch (m.FieldType)
					{
					case typeof(int8), typeof(int16), typeof(int32), typeof(int64), typeof(int):
						int64 integer = 0;
						Span<uint8>((uint8*)val.DataPtr, m.FieldType.Size).CopyTo(Span<uint8>((uint8*)&integer, sizeof(int64)));
						integer.ToString(buffer);
					default: // unsigned
						uint64 integer = 0;
						Span<uint8>((uint8*)val.DataPtr, m.FieldType.Size).CopyTo(Span<uint8>((uint8*)&integer, sizeof(uint64)));
						integer.ToString(buffer);
					}
				}
				else if (m.FieldType.IsFloatingPoint)
				{
					switch (m.FieldType)
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
				else if (m.FieldType is SizedArrayType)
				{
					buffer.Append("[\n");

					let t = (SizedArrayType)m.FieldType;
					let count = t.ElementCount;
					let arrType = t.UnderlyingType;

					var ptr = (uint8*)val.DataPtr;
					for (let i < count)
					{
						var arrVal = Variant.CreateReference(arrType, ptr);
						if (CallSerializeOnField(ref arrVal, arrType, buffer))
							buffer.Append(",\n");

						ptr += arrType.Size;
					}

					buffer.Append("]");
				}
				else if (m.FieldType.IsEnum)
				{
					if (m.FieldType.IsUnion)
					{
						Log.Debug("Cannot serialize union enum");
					}
					else
					{
						int64 value = 0;
						Span<uint8>((uint8*)val.DataPtr, m.FieldType.Size).CopyTo(Span<uint8>((uint8*)&value, sizeof(int64)));
						Enum.EnumToString(m.FieldType, buffer, value);
					}
				}
				else if (m.FieldType.IsStruct)
				{
					CallSerializeOnField(ref val, m.FieldType, buffer);
				}
				else
				{
					Log.Debug($"Couldn't serialize filed: {m.FieldType.GetName(.. scope .())}");
				}

				buffer.Append(",\n");

				val.Dispose();
			}

			buffer.Append("}");

			return true;
		}

		bool CallSerializeOnField(ref Variant val, Type fieldType, String buffer)
		{
			// Fake reflection info for pile types
			switch (fieldType)
			{
			case typeof(Pile.Rect):
				val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(Rect)) & ~1) + (val.[Friend]mStructType & 1);
				return Serialize(typeof(Rect), val, buffer);
			case typeof(Pile.Vector2):
				val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(Vector2)) & ~1) + (val.[Friend]mStructType & 1);
				return Serialize(typeof(Vector2), val, buffer);
			case typeof(Pile.Point2):
				val.[Friend]mStructType = ((int)Internal.UnsafeCastToPtr(typeof(Point2)) & ~1) + + (val.[Friend]mStructType & 1);
				return Serialize(typeof(Point2), val, buffer);
			default:
				return Serialize(fieldType, val, buffer);
			}
		}

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
	}
}
