import Foundation
import LanternKit
import Testing

/// 시간대를 고정한 달력. 테스트가 실행하는 맥의 시간대에 따라 결과가 달라지지 않게 한다
private let seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
    seoul.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Suite("언제까지 옵션")
struct AwakeOptionTests {
    @Test("시간 옵션은 시작 시각에서 더한다") func hoursAddToStart() {
        #expect(AwakeOption.hours(2).endDate(startingAt: date(24, 14, 30), calendar: seoul) == date(24, 16, 30))
    }

    @Test("아직 안 지난 시각은 오늘") func upcomingTimeIsToday() {
        #expect(AwakeOption.timeOfDay(hour: 18, minute: 0).endDate(startingAt: date(24, 14, 30), calendar: seoul) == date(24, 18, 0))
    }

    @Test("이미 지난 시각은 다음 날") func pastTimeRollsOverToNextDay() {
        #expect(AwakeOption.timeOfDay(hour: 7, minute: 0).endDate(startingAt: date(24, 23, 0), calendar: seoul) == date(25, 7, 0))
    }

    @Test("계속과 에이전트는 종료 시각이 없다") func indefiniteAndAgentsHaveNoEnd() {
        #expect(AwakeOption.indefinite.endDate(startingAt: date(24, 14, 0), calendar: seoul) == nil)
        #expect(AwakeOption.untilAgentsFinish.endDate(startingAt: date(24, 14, 0), calendar: seoul) == nil)
    }
}

@Suite("세션 관리")
struct AwakeSessionMachineTests {
    @Test("켜고 끄기") func startAndStop() {
        var machine = AwakeSessionMachine()
        #expect(!machine.isAwake)

        machine.start(.hours(1), at: date(24, 14, 0), calendar: seoul)
        #expect(machine.isAwake)

        let ended = machine.stop()
        #expect(ended?.option == .hours(1))
        #expect(!machine.isAwake)
    }

    @Test("시간이 다 되면 tick에서 끝난다") func tickEndsWhenTimeIsUp() {
        var machine = AwakeSessionMachine()
        machine.start(.hours(1), at: date(24, 14, 0), calendar: seoul)

        #expect(machine.tick(at: date(24, 14, 59)) == nil)
        #expect(machine.isAwake)

        #expect(machine.tick(at: date(24, 15, 0)) == .timeElapsed)
        #expect(!machine.isAwake)
    }

    @Test("계속은 시간이 지나도 끝나지 않는다") func indefiniteNeverExpires() {
        var machine = AwakeSessionMachine()
        machine.start(.indefinite, at: date(24, 14, 0), calendar: seoul)
        #expect(machine.tick(at: date(30, 14, 0)) == nil)
        #expect(machine.isAwake)
    }

    @Test("빠르게 켜기는 마지막 옵션을 지금 기준으로 다시 계산한다") func quickStartRecomputesLastOption() {
        var machine = AwakeSessionMachine()
        machine.start(.hours(2), at: date(24, 9, 0), calendar: seoul)
        machine.stop()

        machine.startWithLastOption(at: date(24, 20, 0), calendar: seoul)
        #expect(machine.current?.endsAt == date(24, 22, 0))
    }

    @Test("남은 시간") func remainingTime() {
        let session = AwakeSession(option: .hours(2), startedAt: date(24, 14, 0), calendar: seoul)
        #expect(session.remaining(at: date(24, 14, 18)) == TimeInterval(102 * 60))
        #expect(session.remaining(at: date(24, 17, 0)) == TimeInterval(0))
    }
}

@Suite("남은 시간 표시")
struct RemainingTimeFormatTests {
    @Test("시와 분으로 표시", arguments: [
        (102.0 * 60, "1:42"),
        (5.0 * 60, "0:05"),
        (90.0, "0:02"),
        (0.0, "0:00"),
        (120.0 * 60, "2:00"),
    ])
    func formatsHoursAndMinutes(remaining: TimeInterval, expected: String) {
        #expect(RemainingTimeFormat.string(from: remaining) == expected)
    }
}

@Suite("깨어 있기 연장")
struct AwakeExtendTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("남은 시간에 더한다 (지금부터 다시 세지 않는다)") func extendsEndDate() throws {
        var machine = AwakeSessionMachine()
        machine.start(.hours(2), at: start)
        let extended = machine.extend(by: 3600)
        #expect(extended)
        let session = try #require(machine.current)
        #expect(session.endsAt == start.addingTimeInterval(3 * 3600))
        #expect(session.startedAt == start)
        #expect(session.option == .hours(2))
    }

    @Test("이미 30분 지난 2시간 세션에 1시간 더하면 2시간 30분 남는다") func keepsRemaining() throws {
        var machine = AwakeSessionMachine()
        machine.start(.hours(2), at: start)
        machine.extend(by: 3600)
        let remaining = try #require(machine.current?.remaining(at: start.addingTimeInterval(30 * 60)))
        #expect(remaining == 2.5 * 3600)
    }

    @Test("끝 시각이 없는 세션은 연장하지 않는다", arguments: [AwakeOption.indefinite, .untilAgentsFinish])
    func cannotExtendOpenEnded(_ option: AwakeOption) {
        var machine = AwakeSessionMachine()
        machine.start(option, at: start)
        let extended = machine.extend(by: 3600)
        #expect(!extended)
        #expect(machine.current?.endsAt == nil)
    }

    @Test("꺼져 있으면 연장하지 않는다") func cannotExtendWhenOff() {
        var machine = AwakeSessionMachine()
        let extended = machine.extend(by: 3600)
        #expect(!extended)
    }
}
