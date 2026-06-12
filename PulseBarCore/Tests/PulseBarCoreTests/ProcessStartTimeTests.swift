import PulseBarCore
import Testing

@Test func processStartTimeEquatable() {
    #expect(ProcessStartTime(seconds: 1, microseconds: 2) == ProcessStartTime(seconds: 1, microseconds: 2))
}
