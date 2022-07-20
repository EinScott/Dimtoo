using Pile;
using System.IO;
using System.Collections;
using System;
using System.Diagnostics;
using Bon;

// TODO: do not include as files, only what we actually need!

namespace Dimtoo
{
	[BonTarget]
	struct SpriteData
	{
		public bool splitLayers;
	}

	[RegisterImporter]
	class AsepriteSpriteImporter : Importer
	{
		public override String Name => "aseprite";

		static StringView[?] ext = .("ase");
		public override Span<StringView> TargetExtensions => ext;

		public override Result<void> Load(StringView name, Span<uint8> data)
		{
			let mem = scope ArrayStream(data);

			Serializer s = scope .(mem);
			let splitLayers = s.Read<uint8>() == 1;

			let ase = scope Aseprite();
			Try!(ase.Parse(mem));

			Point2 origin = .Zero;
			for (let slice in ase.Slices)
				if (slice.Name == "origin" && slice.Pivot != null)
				{
					origin = slice.Pivot.Value;
				}

			if (!splitLayers)
			{
				let frames = scope List<Frame>();
				let frameName = scope String();
				int i = 0;
				for (let frame in ase.Frames)
				{
					// Frame texture name
					frameName..Set(name)..Append(':');
					i.ToString(frameName);
					let subTex = Importer.SubmitLoadedTextureAsset(frameName, frame.Bitmap);

					// Add frame
					frames.Add(Frame(subTex, frame.Duration));
					i++;
				}

				let animations = scope List<(String name, Animation anim)>();
				for (let tag in ase.Tags)
				{
					let animName = new String(tag.Name);
					animations.Add((animName, Animation(tag.From, tag.To, animName)));
				}
	
				let asset = new Sprite(frames, animations, origin);
				if (Importer.SubmitLoadedAsset(name, asset) case .Ok)
					return .Ok;
				else
				{
					delete asset;
					return .Err;
				}
			}
			else
			{
				// TODO: if a layer has no frams for an animation, dont make it have that animation!

				let celMap = scope Bitmap(ase.Width, ase.Height);
				for (let layer in ase.Layers)
				{
					let frames = scope List<Frame>();
					let frameName = scope String();
					int iFrame = 0;
					for (let frame in ase.Frames)
					{
						// Frame texture name
						frameName..Set(name)..Append(':')..Append(layer.Name);
						iFrame.ToString(frameName);
						Aseprite.Cel cel = null;
						for (let i < frame.Cels.Count)
							if (frame.Cels[i].Layer == layer)
							{
								cel = frame.Cels[i];
								break;
							}
						if (cel == null)
							continue;

						// Do this to keep offsets in tact... it's simpler to just let the packer take care of
						// stripping the edges again... although it's not that nice either...
						celMap.Clear();
						celMap.SetPixels(.(cel.X, cel.Y, cel.Width, cel.Height), cel.Pixels);
						let subTex = Importer.SubmitLoadedTextureAsset(frameName, celMap);

						// Add frame
						frames.Add(Frame(subTex, frame.Duration));
						iFrame++;
					}

					let animations = scope List<(String name, Animation anim)>();
					for (let tag in ase.Tags)
					{
						let animName = new String(tag.Name);
						animations.Add((animName, Animation(tag.From, tag.To, animName)));
					}

					let asset = new Sprite(frames, animations, origin);
					if (Importer.SubmitLoadedAsset(ase.Layers.Count > 1 ? scope $"{name}:{layer.Name}" : name, asset) case .Err)
					{
						delete asset;
						return .Err;
					}
				}
				return .Ok;
			}
		}

		public override Result<uint8[]> Build(StringView filePath)
		{
			let metaFilePath = ToScopedMetaFilePath!(filePath);
			var tileData = SpriteData();
			if (File.Exists(metaFilePath))
			{
				let bonMetaFile = File.ReadAllText(metaFilePath, .. scope .());
				if (Bon.Deserialize(ref tileData, bonMetaFile) case .Err)
					LogErrorReturn!("AsepriteImporter: Error deserializing sprite data from bon file structure");
			}

			uint8[] data = null;
			if (ReadFullFile(filePath, ref data) case .Err)
				LogErrorReturn!("AsepriteImporter: Error reading ase file content");
			defer delete data;

			ArrayStream s = scope .(data.Count + 1);
			{
				Serializer sr = scope .(s);

				sr.Write((uint8)(tileData.splitLayers ? 1 : 0));
				if (sr.HadError)
					LogErrorReturn!("AsepriteImporter: Error writing sprite data");
			}

			if (!(s.TryWrite(data) case .Ok(data.Count)))
				LogErrorReturn!("AsepriteImporter: Failed to write data to arrayStream");

			return s.TakeOwnership();
		}
	}

	// TODO: support spacing

	[BonTarget]
	class TilesetData
	{
		public int tileSizeX;
		public int tileSizeY;
		public List<TileCorner> tiles ~ DeleteNotNull!(_);
	}

	[RegisterImporter]
	class AsepriteTilesetImporter : Importer
	{
		public override String Name => "aseTile";

		static StringView[?] ext = .("ase");
		public override Span<StringView> TargetExtensions => ext;

		public override Result<void> Load(StringView name, Span<uint8> data)
		{
			let corners = scope List<(TileCorner corner, UPoint2 spriteOffset)>();
			UPoint2 tileSize;
			let s = scope ArrayStream(data);
			{
				let sr = scope Serializer(s);

				tileSize.X = sr.Read<uint32>();
				tileSize.Y = sr.Read<uint32>();

				let count = sr.Read<uint32>();

				for (let i < count)
				{
					Tile[4] tiles;
					tiles[0] = (.)sr.Read<uint8>();
					tiles[1] = (.)sr.Read<uint8>();
					tiles[2] = (.)sr.Read<uint8>();
					tiles[3] = (.)sr.Read<uint8>();
					corners.Add((TileCorner{tiles = tiles}, .Zero));
				}
			}

			let ase = scope Aseprite();
			Try!(ase.Parse(s));

			int iCorner = 0;
			for (let y < ase.Height / tileSize.Y)
				for (let x < ase.Width / tileSize.X)
				{
					if (iCorner >= corners.Count)
						break;
					corners[iCorner++].spriteOffset = UPoint2(x, y) * tileSize;
				}

			let celMap = scope Bitmap(ase.Width, ase.Height);
			for (let layer in ase.Layers)
			{
				let frames = scope List<Frame>();
				let frameName = scope String();
				int iFrame = 0;
				for (let frame in ase.Frames)
				{
					// Frame texture name
					frameName..Set(name)..Append(':')..Append(layer.Name);
					iFrame.ToString(frameName);
					Aseprite.Cel cel = null;
					for (let i < frame.Cels.Count)
						if (frame.Cels[i].Layer == layer)
						{
							cel = frame.Cels[i];
							break;
						}
					if (cel == null)
						continue;

					// Do this to keep offsets in tact... it's simpler to just let the packer take care of
					// stripping the edges again... although it's not that nice either...
					celMap.Clear();
					celMap.SetPixels(.(cel.X, cel.Y, cel.Width, cel.Height), cel.Pixels);
					let subTex = Importer.SubmitLoadedTextureAsset(frameName, celMap);

					// Add frame
					frames.Add(Frame(subTex, frame.Duration));
					iFrame++;
				}

				let animations = scope List<(String name, Animation anim)>();
				for (let tag in ase.Tags)
				{
					let animName = new String(tag.Name);
					animations.Add((animName, Animation(tag.From, tag.To, animName)));
				}

				let asset = new Tileset(frames, corners, animations, tileSize);
				if (Importer.SubmitLoadedAsset(ase.Layers.Count > 1 ? scope $"{name}:{layer.Name}" : name, asset) case .Err)
				{
					delete asset;
					return .Err;
				}
			}
			return .Ok;
		}

		public override Result<uint8[]> Build(StringView filePath)
		{
			let metaFilePath = ToScopedMetaFilePath!(filePath);

			if (!File.Exists(metaFilePath))
				LogErrorReturn!("AsepriteTileImporter: No tile .bon file of the same name found");

			let bonMetaFile = File.ReadAllText(metaFilePath, .. scope .());
			var tileData = scope TilesetData();
			if (Bon.Deserialize(ref tileData, bonMetaFile) case .Err)
				LogErrorReturn!("AsepriteTileImporter: Error deserializing tile data from bon file structure");

			uint8[] data = null;
			if (ReadFullFile(filePath, ref data) case .Err)
				LogErrorReturn!("AsepriteTileImporter: Error reading ase file content");
			defer delete data;

			ArrayStream s = scope .(data.Count + sizeof(uint32) * 3 + tileData.tiles.Count * sizeof(uint32));
			{
				Serializer sr = scope .(s);

				sr.Write((uint32)tileData.tileSizeX);
				sr.Write((uint32)tileData.tileSizeY);

				sr.Write((uint32)tileData.tiles.Count);

				for (let corner in tileData.tiles)
				{
					sr.Write((uint8)corner.tiles[0]);
					sr.Write((uint8)corner.tiles[1]);
					sr.Write((uint8)corner.tiles[2]);
					sr.Write((uint8)corner.tiles[3]);
				}

				if (sr.HadError)
					LogErrorReturn!("AsepriteTileImporter: Error writing tile data");
			}

			if (!(s.TryWrite(data) case .Ok(data.Count)))
				LogErrorReturn!("AsepriteTileImporter: Failed to write data to arrayStream");

			return s.TakeOwnership();
		}
	}
}
