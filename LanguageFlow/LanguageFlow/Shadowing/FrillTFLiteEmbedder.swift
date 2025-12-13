//
//  FrillTFLiteEmbedder.swift
//  LanguageFlow
//
//  Created by zhangpeibj01 on 12/13/25.
//

import Foundation
import TensorFlowLite

nonisolated
final class FrillTFLiteEmbedder {
    static let sampleRate: Int = 16_000
    static let embDim: Int = 2_048
    static let minSamples: Int = 16_000  // pad to >= 1s to avoid empty outputs

    private let interpreter: Interpreter
    private let inputIndex: Int
    private var outputIndex: Int
    private var didLogRuntimeTensorInfo: Bool = false

    init(modelFileName: String = "frill", modelFileExt: String = "tflite", threadCount: Int = 2) throws {
        guard let modelPath = Bundle.main.path(forResource: modelFileName, ofType: modelFileExt) else {
            throw NSError(domain: "FrillTFLiteEmbedder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file not found in bundle"])
        }

        var options = Interpreter.Options()
        options.threadCount = threadCount

        self.interpreter = try Interpreter(modelPath: modelPath, options: options)
        try interpreter.allocateTensors()

        self.inputIndex = 0
        self.outputIndex = 0

        do {
            let input = try interpreter.input(at: inputIndex)
            ShadowingDebug.log("TFLite init model=\(modelFileName).\(modelFileExt) input name=\(input.name) type=\(input.dataType) shape=\(input.shape.dimensions) bytes=\(input.data.count)")
        } catch {
            ShadowingDebug.log("TFLite init input inspect/resize failed: \(ShadowingDebug.describe(error))")
        }

        logModelInfo(modelFileName: modelFileName, modelFileExt: modelFileExt)
        warmupAndSelectOutputIndex()
    }

    /// 输入：单窗 waveform，长度必须 == win，float32
    /// 输出：embedding[2048]，已 L2 normalize
    func embedWindow(_ window: [Float]) throws -> [Float] {
        guard window.count > 0 else {
            throw NSError(
                domain: "FrillTFLiteEmbedder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid window length \(window.count)"]
            )
        }

        try resizeInputIfNeeded(samples: window.count)

        // 写入输入 tensor
        let inputData = window.withUnsafeBufferPointer { Data(buffer: $0) }
        try interpreter.copy(inputData, toInputAt: inputIndex)
        try interpreter.invoke()

        let outputTensor = try outputTensorAfterInvoke()
        if ShadowingDebug.enabled, !didLogRuntimeTensorInfo {
            didLogRuntimeTensorInfo = true
            do {
                let input = try interpreter.input(at: inputIndex)
                ShadowingDebug.log("TFLite runtime input name=\(input.name) type=\(input.dataType) shape=\(input.shape.dimensions) bytes=\(input.data.count)")
            } catch {
                ShadowingDebug.log("TFLite runtime input inspect failed: \(ShadowingDebug.describe(error))")
            }
            ShadowingDebug.log("TFLite runtime output name=\(outputTensor.name) type=\(outputTensor.dataType) shape=\(outputTensor.shape.dimensions) bytes=\(outputTensor.data.count)")
        }
        let out = outputTensor.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
            let buf = ptr.bindMemory(to: Float32.self)
            return Array(buf)
        }

        // 有些模型输出是 [1,2048] flatten 后长度可能是 2048 或 2048*N
        // 常见情况 out.count == 2048 或 2048*1
        let emb: [Float]
        if out.count == Self.embDim {
            emb = out
        } else if out.count == Self.embDim * 1 {
            emb = Array(out.prefix(Self.embDim))
        } else {
            // 兜底：取前 2048
            emb = Array(out.prefix(Self.embDim))
        }

        return l2Normalize(emb)
    }

    /// 输入：整句 waveform（16k mono），返回 embedding 序列 [T][2048]
    func embedSequence(waveform: [Float]) throws -> [[Float]] {
        var x = waveform
        if x.count < Self.minSamples {
            x += Array(repeating: 0, count: Self.minSamples - x.count)
        }

        // Prefer a single invoke on the full waveform; many speech embedding models (TRILL/FRILL)
        // output a sequence [T, 2048] for variable-length inputs.
        do {
            return try embedSequenceOnce(waveform: x)
        } catch let e as InterpreterError where e == .invokeInterpreterRequired {
            ShadowingDebug.log("TFLite embedSequenceOnce empty output; retry with 2s padding")
            if x.count < Self.minSamples * 2 {
                x += Array(repeating: 0, count: Self.minSamples * 2 - x.count)
            }
            return try embedSequenceOnce(waveform: x)
        } catch {
            return try embedSequenceOnce(waveform: x)
        }
    }

    private func l2Normalize(_ v: [Float]) -> [Float] {
        var sum: Float = 0
        for x in v { sum += x * x }
        let norm = sqrt(sum) + 1e-8
        return v.map { $0 / norm }
    }

    private func resizeInputIfNeeded(samples: Int) throws {
        let input = try interpreter.input(at: inputIndex)
        let rank = input.shape.dimensions.count
        let current = input.shape.dimensions

        let desired: [Int]
        if rank == 1 {
            desired = [samples]
        } else {
            desired = [1, samples]
        }

        guard current != desired else { return }

        try interpreter.resizeInput(at: inputIndex, to: Tensor.Shape(desired))
        try interpreter.allocateTensors()

        let resized = try interpreter.input(at: inputIndex)
        ShadowingDebug.log("TFLite resized input shape=\(resized.shape.dimensions) bytes=\(resized.data.count)")
    }

    private func embedSequenceOnce(waveform: [Float]) throws -> [[Float]] {
        try resizeInputIfNeeded(samples: waveform.count)

        let inputData = waveform.withUnsafeBufferPointer { Data(buffer: $0) }
        try interpreter.copy(inputData, toInputAt: inputIndex)
        try interpreter.invoke()

        let outTensor = try outputTensorAfterInvoke()
        if ShadowingDebug.enabled, !didLogRuntimeTensorInfo {
            didLogRuntimeTensorInfo = true
            do {
                let input = try interpreter.input(at: inputIndex)
                ShadowingDebug.log("TFLite runtime input name=\(input.name) type=\(input.dataType) shape=\(input.shape.dimensions) bytes=\(input.data.count)")
            } catch {
                ShadowingDebug.log("TFLite runtime input inspect failed: \(ShadowingDebug.describe(error))")
            }
            ShadowingDebug.log("TFLite runtime output name=\(outTensor.name) type=\(outTensor.dataType) shape=\(outTensor.shape.dimensions) bytes=\(outTensor.data.count)")
        }

        let flat = outTensor.data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> [Float] in
            let buf = ptr.bindMemory(to: Float32.self)
            return Array(buf)
        }

        guard !flat.isEmpty else {
            throw InterpreterError.invokeInterpreterRequired
        }

        if flat.count == Self.embDim {
            return [l2Normalize(flat)]
        }

        if flat.count % Self.embDim == 0 {
            let t = flat.count / Self.embDim
            var seq: [[Float]] = []
            seq.reserveCapacity(t)
            for i in 0..<t {
                let start = i * Self.embDim
                let end = start + Self.embDim
                seq.append(l2Normalize(Array(flat[start..<end])))
            }
            return seq
        }

        // Fallback: take the first embDim values (best-effort).
        if flat.count > Self.embDim {
            return [l2Normalize(Array(flat.prefix(Self.embDim)))]
        }

        throw NSError(
            domain: "FrillTFLiteEmbedder",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected output element count \(flat.count), expected multiple of \(Self.embDim)"]
        )
    }

    private func logModelInfo(modelFileName: String, modelFileExt: String) {
        guard ShadowingDebug.enabled else { return }
        ShadowingDebug.log("TFLite info inputs=\(interpreter.inputTensorCount) outputs=\(interpreter.outputTensorCount) signatureKeys=\(interpreter.signatureKeys)")
        for i in 0..<interpreter.inputTensorCount {
            do {
                let t = try interpreter.input(at: i)
                ShadowingDebug.log("TFLite input[\(i)] name=\(t.name) type=\(t.dataType) shape=\(t.shape.dimensions) bytes=\(t.data.count)")
            } catch {
                ShadowingDebug.log("TFLite input[\(i)] inspect failed: \(ShadowingDebug.describe(error))")
            }
        }

        // Output tensor info may not be accessible before the first invoke for dynamic-output models.
        for i in 0..<interpreter.outputTensorCount {
            do {
                let t = try interpreter.output(at: i)
                ShadowingDebug.log("TFLite output[\(i)] (pre-invoke) name=\(t.name) type=\(t.dataType) shape=\(t.shape.dimensions) bytes=\(t.data.count)")
            } catch {
                ShadowingDebug.log("TFLite output[\(i)] pre-invoke inspect failed: \(ShadowingDebug.describe(error))")
            }
        }
    }

    private func warmupAndSelectOutputIndex() {
        guard interpreter.outputTensorCount > 0 else { return }

        do {
            let probeSamples = Self.minSamples
            try resizeInputIfNeeded(samples: probeSamples)
            let zeros = [Float](repeating: 0, count: probeSamples)
            let inputData = zeros.withUnsafeBufferPointer { Data(buffer: $0) }
            try interpreter.copy(inputData, toInputAt: inputIndex)
            try interpreter.invoke()
        } catch {
            ShadowingDebug.log("TFLite warmup invoke failed: \(ShadowingDebug.describe(error))")
            return
        }

        var bestIndex: Int?
        var bestPriority: Int = -1
        var bestElementCount: Int = 0
        for i in 0..<interpreter.outputTensorCount {
            do {
                let t = try interpreter.output(at: i)
                ShadowingDebug.log("TFLite output[\(i)] (post-invoke) name=\(t.name) type=\(t.dataType) shape=\(t.shape.dimensions) bytes=\(t.data.count)")

                guard t.dataType == .float32 else { continue }
                let elemCount = t.data.count / MemoryLayout<Float32>.size
                guard elemCount >= Self.embDim else { continue }

                let lastDimMatches = (t.shape.dimensions.last == Self.embDim)
                let isMultiple = (elemCount % Self.embDim == 0)
                let priority: Int
                if elemCount == Self.embDim {
                    priority = 3
                } else if lastDimMatches, isMultiple {
                    priority = 2
                } else if isMultiple {
                    priority = 1
                } else {
                    priority = 0
                }

                if priority > bestPriority || (priority == bestPriority && elemCount > bestElementCount) {
                    bestIndex = i
                    bestPriority = priority
                    bestElementCount = elemCount
                }
            } catch {
                ShadowingDebug.log("TFLite output[\(i)] post-invoke inspect failed: \(ShadowingDebug.describe(error))")
            }
        }

        if let bestIndex {
            outputIndex = bestIndex
            ShadowingDebug.log("TFLite selected outputIndex=\(bestIndex) elements=\(bestElementCount) priority=\(bestPriority)")
        } else {
            ShadowingDebug.log("TFLite selected outputIndex fallback=0")
        }
    }

    private func outputTensorAfterInvoke() throws -> Tensor {
        do {
            return try interpreter.output(at: outputIndex)
        } catch {
            ShadowingDebug.log("TFLite output[\(outputIndex)] read failed after invoke: \(ShadowingDebug.describe(error))")
        }

        var lastError: Error?
        var bestTensor: Tensor?
        var bestIndex: Int?
        var bestPriority: Int = -1
        var bestElementCount: Int = 0

        for i in 0..<interpreter.outputTensorCount {
            do {
                let t = try interpreter.output(at: i)
                ShadowingDebug.log("TFLite output[\(i)] (fallback) name=\(t.name) type=\(t.dataType) shape=\(t.shape.dimensions) bytes=\(t.data.count)")

                guard t.dataType == .float32 else { continue }
                let elemCount = t.data.count / MemoryLayout<Float32>.size
                guard elemCount >= Self.embDim else { continue }

                let lastDimMatches = (t.shape.dimensions.last == Self.embDim)
                let isMultiple = (elemCount % Self.embDim == 0)
                let priority: Int
                if elemCount == Self.embDim {
                    priority = 3
                } else if lastDimMatches, isMultiple {
                    priority = 2
                } else if isMultiple {
                    priority = 1
                } else {
                    priority = 0
                }

                if priority > bestPriority || (priority == bestPriority && elemCount > bestElementCount) {
                    bestTensor = t
                    bestIndex = i
                    bestPriority = priority
                    bestElementCount = elemCount
                }
            } catch {
                lastError = error
                ShadowingDebug.log("TFLite output[\(i)] fallback read failed: \(ShadowingDebug.describe(error))")
            }
        }

        if let bestTensor, let bestIndex {
            outputIndex = bestIndex
            ShadowingDebug.log("TFLite outputIndex updated=\(bestIndex) elements=\(bestElementCount) priority=\(bestPriority)")
            return bestTensor
        }

        throw lastError ?? InterpreterError.invokeInterpreterRequired
    }
}
