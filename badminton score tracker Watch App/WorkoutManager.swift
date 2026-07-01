import Foundation
import HealthKit

@MainActor
final class WorkoutManager: ObservableObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var isActive = false
    @Published var authorized = false

    private let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType()
    ]
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType()
    ]

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            authorized = true
        } catch {
            authorized = false
        }
    }

    func startWorkout(startDate: Date) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if !authorized { await requestAuthorization() }

        let config = HKWorkoutConfiguration()
        config.activityType = .badminton
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            self.session = session
            self.builder = builder
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            isActive = true
        } catch {
            isActive = false
        }
    }

    func endWorkout() async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: Date())
            try await builder.finishWorkout()
        } catch {
            // Best-effort teardown: the session is ending regardless, so a
            // failed finish has nothing actionable to recover — just proceed.
        }
        self.session = nil
        self.builder = nil
        isActive = false
    }
}
