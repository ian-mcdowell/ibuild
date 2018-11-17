
import llbuildSwift
import Foundation

extension Collection {

    /// Returns the element at the specified index iff it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}


// class SimpleTask: Task {
//   let inputs: [Key]
//   var values: [Int]
	
//   init(_ inputs: [Key]) {
//     self.inputs = inputs
//     values = [Int](repeating: 0, count: inputs.count)
//   }
	
//   func start(_ engine: TaskBuildEngine) {
//     for (idx, input) in inputs.enumerated() {
//       engine.taskNeedsInput(input, inputID: idx)
//     }
//   }
  
//   func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
//     values[inputID] = Int(value.toString())!
//   }
  
//   func inputsAvailable(_ engine: TaskBuildEngine) {
//     // let result = compute(values)
//     engine.taskIsComplete(Value("test"), forceChange: false)
//   }
// }



// class FetchLocationRule: Rule {
//   let location: Package.Location
//   init(_ location: Package.Location) { 
//     self.location = location
//   } 
//   func createTask() -> Task {
//     switch self {
//     case .github(let path, _):
//         return URL(string: "https://github.com/\(path).git")!
//     case .git(let url, _), .tar(let url):
//         return url
//     case .local(let path):
//         let url: URL
//         // TODO
//         // if path.hasPrefix("/") {
//             url = URL(fileURLWithPath: path).standardizedFileURL
//         // } else {
//         //     url = packageRoot.appendingPathComponent(path).standardizedFileURL
//         // }
//         return url
//     }
//     return SimpleTask(inputs)
//   }
// }


// class FetchGitPackageTask: Task {
//   let url: URL
//   var values: [Int]
	
//   init(_ url: URL) {
//     self.url = url
//     values = [Int](repeating: 0, count: inputs.count)
//   }
	
//   func start(_ engine: TaskBuildEngine) {
//     for (idx, input) in inputs.enumerated() {
//       engine.taskNeedsInput(input, inputID: idx)
//     }
//   }
  
//   func provideValue(_ engine: TaskBuildEngine, inputID: Int, value: Value) {
//     values[inputID] = Int(value.toString())!
//   }
  
//   func inputsAvailable(_ engine: TaskBuildEngine) {
//     // let result = compute(values)
//     engine.taskIsComplete(Value("test"), forceChange: false)
//   }
// }
