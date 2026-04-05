import Testing
@testable import Tekkon

@Suite("LegalMixedInputFixtureTests", .serialized)
struct LegalMixedInputFixtureTests {
  @Test func zhuyinFixturesAreLegallyComposable() {
    for fixture in LegalMixedInputFixtures.zhuyinStandard {
      var composer = Tekkon.Composer(arrange: fixture.parser)
      let result = composer.receiveSequence(fixture.typing)
      #expect(result == fixture.expectedPhonabet, "Fixture \(fixture.label) should be legal under \(fixture.parser.nameTag): \(fixture.typing) -> \(result), expected \(fixture.expectedPhonabet)")
      #expect(composer.hasIntonation(), "Fixture \(fixture.label) should include a valid tone")
    }
  }

  @Test func hanyuPinyinFixturesAreLegallyComposable() {
    for fixture in LegalMixedInputFixtures.hanyuPinyin {
      var composer = Tekkon.Composer(arrange: fixture.parser)
      let result = composer.receiveSequence(fixture.typing)
      #expect(result == fixture.expectedPhonabet, "Fixture \(fixture.label) should be legal under \(fixture.parser.nameTag): \(fixture.typing) -> \(result), expected \(fixture.expectedPhonabet)")
      #expect(composer.hasIntonation(), "Fixture \(fixture.label) should include a valid tone")
    }
  }
}
