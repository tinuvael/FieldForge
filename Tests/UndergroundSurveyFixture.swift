import XCTest
#if canImport(FieldForgeCore)
@testable import FieldForgeCore
#else
@testable import FieldForge
#endif

/// Test-only ASCII DXF writer. Coordinates are lexical strings, avoiding
/// platform-dependent floating-point formatting. No Python/runtime tool needed.
enum UndergroundSurveyFixture {
    private struct Wall: Decodable {
        let handle: String, layer: String
        let vertices: [[String]]
    }
    private struct Manifest: Decodable { let sha256: String }

    static func bytes(level: Int, geometry: Data, manifest: Data) throws -> Data {
        let walls = try XCTUnwrap(JSONDecoder().decode([String: [Wall]].self, from: geometry)[String(level)])
        var text = ""
        func add(_ pairs: (Int, String)...) {
            for (code, value) in pairs { text += "\(code)\n\(value)\n" }
        }
        func hex(_ value: Int) -> String { String(value, radix: 16, uppercase: true) }
        add((0, "SECTION"), (2, "HEADER"), (9, "$ACADVER"), (1, "AC1032"),
            (9, "$HANDSEED"), (5, "10000"), (9, "$INSUNITS"), (70, "6"),
            (9, "$MEASUREMENT"), (70, "1"), (0, "ENDSEC"))
        add((0, "SECTION"), (2, "TABLES"), (0, "TABLE"), (2, "LTYPE"), (5, "10"),
            (100, "AcDbSymbolTable"), (70, "1"), (0, "LTYPE"), (5, "11"), (330, "10"),
            (100, "AcDbSymbolTableRecord"), (100, "AcDbLinetypeTableRecord"), (2, "CONTINUOUS"),
            (70, "0"), (3, "Solid line"), (72, "65"), (73, "0"), (40, "0"), (0, "ENDTAB"),
            (0, "TABLE"), (2, "LAYER"), (5, "12"), (100, "AcDbSymbolTable"), (70, String(walls.count + 1)))
        for (i, layer) in (["0"] + walls.map(\.layer)).enumerated() {
            add((0, "LAYER"), (5, hex(0x20 + i)), (330, "12"), (100, "AcDbSymbolTableRecord"),
                (100, "AcDbLayerTableRecord"), (2, layer), (70, "0"),
                (62, layer.contains("LEFT") ? "3" : "5"), (6, "CONTINUOUS"))
        }
        add((0, "ENDTAB"), (0, "TABLE"), (2, "BLOCK_RECORD"), (5, "13"), (100, "AcDbSymbolTable"), (70, "2"))
        for (handle, name) in [("14", "*Model_Space"), ("15", "*Paper_Space")] {
            add((0, "BLOCK_RECORD"), (5, handle), (330, "13"), (100, "AcDbSymbolTableRecord"),
                (100, "AcDbBlockTableRecord"), (2, name), (70, "0"))
        }
        add((0, "ENDTAB"), (0, "ENDSEC"), (0, "SECTION"), (2, "BLOCKS"))
        for (handle, owner, name) in [(0x16, "14", "*Model_Space"), (0x18, "15", "*Paper_Space")] {
            add((0, "BLOCK"), (5, hex(handle)), (330, owner), (100, "AcDbEntity"), (8, "0"),
                (100, "AcDbBlockBegin"), (2, name), (70, "0"), (10, "0"), (20, "0"), (30, "0"),
                (3, name), (1, ""), (0, "ENDBLK"), (5, hex(handle + 1)), (330, owner),
                (100, "AcDbEntity"), (8, "0"), (100, "AcDbBlockEnd"))
        }
        add((0, "ENDSEC"), (0, "SECTION"), (2, "ENTITIES"))
        for wall in walls {
            let handle = try XCTUnwrap(Int(wall.handle, radix: 16))
            add((0, "POLYLINE"), (5, wall.handle), (330, "14"), (100, "AcDbEntity"), (8, wall.layer),
                (100, "AcDb3dPolyline"), (66, "1"), (10, "0"), (20, "0"), (30, "0"), (70, "8"))
            for (i, vertex) in wall.vertices.enumerated() {
                guard vertex.count == 3 else { throw StorageError.invalidRecord }
                add((0, "VERTEX"), (5, hex(handle + i + 1)), (330, wall.handle), (100, "AcDbEntity"),
                    (8, wall.layer), (100, "AcDbVertex"), (100, "AcDb3dPolylineVertex"),
                    (10, vertex[0]), (20, vertex[1]), (30, vertex[2]), (70, "32"))
            }
            add((0, "SEQEND"), (5, hex(handle + wall.vertices.count + 1)), (330, wall.handle),
                (100, "AcDbEntity"), (8, wall.layer))
        }
        add((0, "ENDSEC"), (0, "EOF"))
        let data = Data(text.utf8)
        let expected = try XCTUnwrap(JSONDecoder().decode([String: Manifest].self, from: manifest)[String(level)])
        guard ManagedPlanStore.digest(data) == expected.sha256 else {
            XCTFail("Generated survey \(level) differs from pinned DXF hash")
            throw StorageError.invalidRecord
        }
        return data
    }
}
