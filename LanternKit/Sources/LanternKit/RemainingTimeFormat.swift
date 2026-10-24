import Foundation

public enum RemainingTimeFormat {
    /// 남은 시간을 "1:42"(시:분)로 만든다.
    ///
    /// 분 단위로 올림한다. 1분 30초 남았으면 "0:02"로, 아직 시간이 남았는데 "0:00"이 보이는 일을 막는다.
    public static func string(from remaining: TimeInterval) -> String {
        let totalMinutes = Int((max(0, remaining) / 60).rounded(.up))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "\(hours):" + (minutes < 10 ? "0\(minutes)" : "\(minutes)")
    }
}
