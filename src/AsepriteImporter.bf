using Pile;
using System.IO;
using System.Collections;
using System;
using System.Diagnostics;
using Atma;

namespace Dimtoo
{
	[RegisterImporter]
	class AsepriteSpriteImporter : Importer
	{
		public String Name => "ase";

		public Result<void> Load(StringView name, Span<uint8> data)
		{
			let mem = scope MemoryStream();
			Try!(mem.TryWrite(data));
			mem.Position = 0;

			let ase = scope Aseprite();
			Try!(ase.Parse(mem));

			let frames = scope List<Frame>();
			let frameName = scope String();
			int i = 0;
			for (let frame in ase.Frames)
			{
				// Frame texture name
				frameName.Set(name);
				i.ToString(frameName);
				let subTex = Importers.SubmitTextureAsset(frameName, frame.Bitmap);

				// Add frame
				frames.Add(Frame(subTex, frame.Duration));
				i++;
			}

			let animations = scope List<(String name, Animation anim)>();
			for (let tag in ase.Tags)
				animations.Add((new String(tag.Name), Animation(tag.From, tag.To)));

			Point2 origin = .Zero;
			for (let slice in ase.Slices)
				if (slice.Name == "origin" && slice.Pivot != null)
				{
					origin = slice.Pivot.Value;
				}

			let asset = new Sprite(frames, animations, origin);
			if (Importers.SubmitAsset(name, asset) case .Ok)
				return .Ok;
			else
			{
				delete asset;
				return .Err;
			}
		}

		public Result<uint8[]> Build(Stream data, Span<StringView> config, StringView dataFilePath)
		{
			return Importer.TryStreamToArray!(data);
		}
	}

	[Atma.SerializableAttribute]
	class TilesetData
	{
		public int tileSizeX;
		public int tileSizeY;
		public List<TileCornerData> tileCorners ~ if (_ != null) DeleteContainerAndItems!(_);

		[Atma.SerializableAttribute]
		public class TileCornerData
		{
			public bool upLeft, upRight, downLeft, downRight;
		}	
	}

	[RegisterImporter]
	class AsepriteTilesetImporter : Importer
	{
		public bool RebuildOnAdditionalChanged => true;

		public String Name => "aseTile";

		public Result<void> Load(StringView name, Span<uint8> data)
		{
			let corners = scope List<(TileCorner corner, UPoint2 tileOffset)>();
			UPoint2 tileSize;
			let s = scope ArrayStream(data);
			{
				let sr = scope Serializer(s);

				tileSize.X = sr.Read<uint32>();
				tileSize.Y = sr.Read<uint32>();

				let count = sr.Read<uint32>();

				for (let i < count)
					corners.Add(((.)sr.Read<uint8>(), .Zero));
			}

			let ase = scope Aseprite();
			Try!(ase.Parse(s));

			int iCorner = 0;
			for (let y < ase.Height / tileSize.Y)
				for (let x < ase.Width / tileSize.X)
				{
					if (iCorner >= corners.Count)
						break;
					corners[iCorner++].tileOffset = UPoint2(x, y) * tileSize;
				}
			
			let frames = scope List<Frame>();
			let frameName = scope String();
			int iFrame = 0;
			for (let frame in ase.Frames)
			{
				// Frame texture name
				frameName.Set(name);
				iFrame.ToString(frameName);
				let subTex = Importers.SubmitTextureAsset(frameName, frame.Bitmap);

				// Add frame
				frames.Add(Frame(subTex, frame.Duration));
				iFrame++;
			}

			let animations = scope List<(String name, Animation anim)>();
			for (let tag in ase.Tags)
				animations.Add((new String(tag.Name), Animation(tag.From, tag.To)));

			let asset = new Tileset(frames, corners, animations, tileSize);
			if (Importers.SubmitAsset(name, asset) case .Ok)
				return .Ok;
			else
			{
				delete asset;
				return .Err;
			}
		}

		public Result<uint8[]> Build(Stream data, Span<StringView> config, StringView dataFilePath)
		{
			let tileFile = Path.ChangeExtension(dataFilePath, "json", .. scope .());
			if (!File.Exists(tileFile))
				LogErrorReturn!("AsepriteTileImporter: No tile .json file of the same name found");

			let json = File.ReadAllText(tileFile, .. scope .());
			let tileData = scope TilesetData();
			if (JsonConvert.Deserialize(tileData, json) case .Err)
				LogErrorReturn!("AsepriteTileImporter: Error deserializing tile data from json file structure");

			ArrayStream s = scope .(data.Length + tileData.tileCorners.Count + sizeof(uint32));
			{
				Serializer sr = scope .(s);

				sr.Write((uint32)tileData.tileSizeX);
				sr.Write((uint32)tileData.tileSizeY);

				sr.Write((uint32)tileData.tileCorners.Count);

				for (let entry in tileData.tileCorners)
				{
					TileCorner corner = .None;

					if (entry.upLeft)
						corner |= .UpLeft;
					if (entry.upRight)
						corner |= .UpRight;

					if (entry.downLeft)
						corner |= .DownLeft;
					if (entry.downRight)
						corner |= .DownRight;

					sr.Write(corner.Underlying);
				}

				if (sr.HadError)
					LogErrorReturn!("AsepriteTileImporter: Error writing tile data. Not sure why this would ever happen");
			}

			let outData = scope uint8[data.Length];
			if (!(data.TryRead(outData) case .Ok(data.Length)))
				LogErrorReturn!("AsepriteTileImporter: Failed to read data from input stream");
			if (!(s.TryWrite(outData) case .Ok(data.Length)))
				LogErrorReturn!("AsepriteTileImporter: Failed to write data to arrayStream");

			return s.TakeOwnership();
		}
	}
}
