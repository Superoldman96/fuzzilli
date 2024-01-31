// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Enum defining all opcodes supported in FuzzIL.
///
/// There should be a 1:1 mapping between opcodes and Operation subclasses.
/// This enum is then mainly used for efficient type testing of Operations, for example in switch constructs:
///
///     switch instr.op.opcode() {
///         case .loadInt(let op):
///             doSomethingWithLoadInteger(op)
///         // ...
///         case .callFunction(let op):
///             doSomethingWithCallFunction(op)
///         // ...
///     }
///
/// This is both efficient, as only an integer value needs to be switched on, and type-safe, as it avoids type casts entirely.
enum Opcode {
    case nop(Nop)
    case loadInteger(LoadInteger)
    case loadBigInt(LoadBigInt)
    case loadFloat(LoadFloat)
    case loadString(LoadString)
    case loadBoolean(LoadBoolean)
    case loadUndefined(LoadUndefined)
    case loadNull(LoadNull)
    case loadThis(LoadThis)
    case loadArguments(LoadArguments)
    case createNamedVariable(CreateNamedVariable)
    case loadDisposableVariable(LoadDisposableVariable)
    case loadAsyncDisposableVariable(LoadAsyncDisposableVariable)
    case loadRegExp(LoadRegExp)
    case beginObjectLiteral(BeginObjectLiteral)
    case objectLiteralAddProperty(ObjectLiteralAddProperty)
    case objectLiteralAddElement(ObjectLiteralAddElement)
    case objectLiteralAddComputedProperty(ObjectLiteralAddComputedProperty)
    case objectLiteralCopyProperties(ObjectLiteralCopyProperties)
    case objectLiteralSetPrototype(ObjectLiteralSetPrototype)
    case beginObjectLiteralMethod(BeginObjectLiteralMethod)
    case endObjectLiteralMethod(EndObjectLiteralMethod)
    case beginObjectLiteralComputedMethod(BeginObjectLiteralComputedMethod)
    case endObjectLiteralComputedMethod(EndObjectLiteralComputedMethod)
    case beginObjectLiteralGetter(BeginObjectLiteralGetter)
    case endObjectLiteralGetter(EndObjectLiteralGetter)
    case beginObjectLiteralSetter(BeginObjectLiteralSetter)
    case endObjectLiteralSetter(EndObjectLiteralSetter)
    case endObjectLiteral(EndObjectLiteral)
    case beginClassDefinition(BeginClassDefinition)
    case beginClassConstructor(BeginClassConstructor)
    case endClassConstructor(EndClassConstructor)
    case classAddInstanceProperty(ClassAddInstanceProperty)
    case classAddInstanceElement(ClassAddInstanceElement)
    case classAddInstanceComputedProperty(ClassAddInstanceComputedProperty)
    case beginClassInstanceMethod(BeginClassInstanceMethod)
    case endClassInstanceMethod(EndClassInstanceMethod)
    case beginClassInstanceGetter(BeginClassInstanceGetter)
    case endClassInstanceGetter(EndClassInstanceGetter)
    case beginClassInstanceSetter(BeginClassInstanceSetter)
    case endClassInstanceSetter(EndClassInstanceSetter)
    case classAddStaticProperty(ClassAddStaticProperty)
    case classAddStaticElement(ClassAddStaticElement)
    case classAddStaticComputedProperty(ClassAddStaticComputedProperty)
    case beginClassStaticInitializer(BeginClassStaticInitializer)
    case endClassStaticInitializer(EndClassStaticInitializer)
    case beginClassStaticMethod(BeginClassStaticMethod)
    case endClassStaticMethod(EndClassStaticMethod)
    case beginClassStaticGetter(BeginClassStaticGetter)
    case endClassStaticGetter(EndClassStaticGetter)
    case beginClassStaticSetter(BeginClassStaticSetter)
    case endClassStaticSetter(EndClassStaticSetter)
    case classAddPrivateInstanceProperty(ClassAddPrivateInstanceProperty)
    case beginClassPrivateInstanceMethod(BeginClassPrivateInstanceMethod)
    case endClassPrivateInstanceMethod(EndClassPrivateInstanceMethod)
    case classAddPrivateStaticProperty(ClassAddPrivateStaticProperty)
    case beginClassPrivateStaticMethod(BeginClassPrivateStaticMethod)
    case endClassPrivateStaticMethod(EndClassPrivateStaticMethod)
    case endClassDefinition(EndClassDefinition)
    case createArray(CreateArray)
    case createIntArray(CreateIntArray)
    case createFloatArray(CreateFloatArray)
    case createArrayWithSpread(CreateArrayWithSpread)
    case createTemplateString(CreateTemplateString)
    case getProperty(GetProperty)
    case setProperty(SetProperty)
    case updateProperty(UpdateProperty)
    case deleteProperty(DeleteProperty)
    case configureProperty(ConfigureProperty)
    case getElement(GetElement)
    case setElement(SetElement)
    case updateElement(UpdateElement)
    case deleteElement(DeleteElement)
    case configureElement(ConfigureElement)
    case getComputedProperty(GetComputedProperty)
    case setComputedProperty(SetComputedProperty)
    case updateComputedProperty(UpdateComputedProperty)
    case deleteComputedProperty(DeleteComputedProperty)
    case configureComputedProperty(ConfigureComputedProperty)
    case typeOf(TypeOf)
    case void(Void_)
    case testInstanceOf(TestInstanceOf)
    case testIn(TestIn)
    case beginPlainFunction(BeginPlainFunction)
    case endPlainFunction(EndPlainFunction)
    case beginArrowFunction(BeginArrowFunction)
    case endArrowFunction(EndArrowFunction)
    case beginGeneratorFunction(BeginGeneratorFunction)
    case endGeneratorFunction(EndGeneratorFunction)
    case beginAsyncFunction(BeginAsyncFunction)
    case endAsyncFunction(EndAsyncFunction)
    case beginAsyncArrowFunction(BeginAsyncArrowFunction)
    case endAsyncArrowFunction(EndAsyncArrowFunction)
    case beginAsyncGeneratorFunction(BeginAsyncGeneratorFunction)
    case endAsyncGeneratorFunction(EndAsyncGeneratorFunction)
    case beginConstructor(BeginConstructor)
    case endConstructor(EndConstructor)
    case directive(Directive)
    case `return`(Return)
    case yield(Yield)
    case yieldEach(YieldEach)
    case await(Await)
    case callFunction(CallFunction)
    case callFunctionWithSpread(CallFunctionWithSpread)
    case construct(Construct)
    case constructWithSpread(ConstructWithSpread)
    case callMethod(CallMethod)
    case callMethodWithSpread(CallMethodWithSpread)
    case callComputedMethod(CallComputedMethod)
    case callComputedMethodWithSpread(CallComputedMethodWithSpread)
    case unaryOperation(UnaryOperation)
    case binaryOperation(BinaryOperation)
    case ternaryOperation(TernaryOperation)
    case update(Update)
    case dup(Dup)
    case reassign(Reassign)
    case destructArray(DestructArray)
    case destructArrayAndReassign(DestructArrayAndReassign)
    case destructObject(DestructObject)
    case destructObjectAndReassign(DestructObjectAndReassign)
    case compare(Compare)
    case eval(Eval)
    case beginWith(BeginWith)
    case endWith(EndWith)
    case callSuperConstructor(CallSuperConstructor)
    case callSuperMethod(CallSuperMethod)
    case getPrivateProperty(GetPrivateProperty)
    case setPrivateProperty(SetPrivateProperty)
    case updatePrivateProperty(UpdatePrivateProperty)
    case callPrivateMethod(CallPrivateMethod)
    case getSuperProperty(GetSuperProperty)
    case setSuperProperty(SetSuperProperty)
    case getComputedSuperProperty(GetComputedSuperProperty)
    case setComputedSuperProperty(SetComputedSuperProperty)
    case updateSuperProperty(UpdateSuperProperty)
    case beginIf(BeginIf)
    case beginElse(BeginElse)
    case endIf(EndIf)
    case beginWhileLoopHeader(BeginWhileLoopHeader)
    case beginWhileLoopBody(BeginWhileLoopBody)
    case endWhileLoop(EndWhileLoop)
    case beginDoWhileLoopBody(BeginDoWhileLoopBody)
    case beginDoWhileLoopHeader(BeginDoWhileLoopHeader)
    case endDoWhileLoop(EndDoWhileLoop)
    case beginForLoopInitializer(BeginForLoopInitializer)
    case beginForLoopCondition(BeginForLoopCondition)
    case beginForLoopAfterthought(BeginForLoopAfterthought)
    case beginForLoopBody(BeginForLoopBody)
    case endForLoop(EndForLoop)
    case beginForInLoop(BeginForInLoop)
    case endForInLoop(EndForInLoop)
    case beginForOfLoop(BeginForOfLoop)
    case beginForOfLoopWithDestruct(BeginForOfLoopWithDestruct)
    case endForOfLoop(EndForOfLoop)
    case beginRepeatLoop(BeginRepeatLoop)
    case endRepeatLoop(EndRepeatLoop)
    case loopBreak(LoopBreak)
    case loopContinue(LoopContinue)
    case beginTry(BeginTry)
    case beginCatch(BeginCatch)
    case beginFinally(BeginFinally)
    case endTryCatchFinally(EndTryCatchFinally)
    case throwException(ThrowException)
    case beginCodeString(BeginCodeString)
    case endCodeString(EndCodeString)
    case beginBlockStatement(BeginBlockStatement)
    case endBlockStatement(EndBlockStatement)
    case beginSwitch(BeginSwitch)
    case beginSwitchCase(BeginSwitchCase)
    case beginSwitchDefaultCase(BeginSwitchDefaultCase)
    case endSwitchCase(EndSwitchCase)
    case endSwitch(EndSwitch)
    case switchBreak(SwitchBreak)
    case loadNewTarget(LoadNewTarget)
    case print(Print)
    case explore(Explore)
    case probe(Probe)
    case fixup(Fixup)
    case beginWasmModule(BeginWasmModule)
    case endWasmModule(EndWasmModule)
    case createWasmGlobal(CreateWasmGlobal)
    case createWasmTable(CreateWasmTable)

    // Wasm opcodes
    case consti64(Consti64)
    case consti32(Consti32)
    case constf32(Constf32)
    case constf64(Constf64)
    case wasmReturn(WasmReturn)
    case wasmJsCall(WasmJsCall)

    // Numerical Operations
    case wasmi32CompareOp(Wasmi32CompareOp)
    case wasmi64CompareOp(Wasmi64CompareOp)
    case wasmf32CompareOp(Wasmf32CompareOp)
    case wasmf64CompareOp(Wasmf64CompareOp)
    case wasmi32EqualZero(Wasmi32EqualZero)
    case wasmi64EqualZero(Wasmi64EqualZero)
    case wasmi32BinOp(Wasmi32BinOp)
    case wasmi64BinOp(Wasmi64BinOp)
    case wasmi32UnOp(Wasmi32UnOp)
    case wasmi64UnOp(Wasmi64UnOp)
    case wasmf32BinOp(Wasmf32BinOp)
    case wasmf64BinOp(Wasmf64BinOp)
    case wasmf32UnOp(Wasmf32UnOp)
    case wasmf64UnOp(Wasmf64UnOp)

    // Numerical Conversion / Truncation operations
    case wasmWrapi64Toi32(WasmWrapi64Toi32)
    case wasmTruncatef32Toi32(WasmTruncatef32Toi32)
    case wasmTruncatef64Toi32(WasmTruncatef64Toi32)
    case wasmExtendi32Toi64(WasmExtendi32Toi64)
    case wasmTruncatef32Toi64(WasmTruncatef32Toi64)
    case wasmTruncatef64Toi64(WasmTruncatef64Toi64)
    case wasmConverti32Tof32(WasmConverti32Tof32)
    case wasmConverti64Tof32(WasmConverti64Tof32)
    case wasmDemotef64Tof32(WasmDemotef64Tof32)
    case wasmConverti32Tof64(WasmConverti32Tof64)
    case wasmConverti64Tof64(WasmConverti64Tof64)
    case wasmPromotef32Tof64(WasmPromotef32Tof64)
    case wasmReinterpretf32Asi32(WasmReinterpretf32Asi32)
    case wasmReinterpretf64Asi64(WasmReinterpretf64Asi64)
    case wasmReinterpreti32Asf32(WasmReinterpreti32Asf32)
    case wasmReinterpreti64Asf64(WasmReinterpreti64Asf64)
    case wasmSignExtend8Intoi32(WasmSignExtend8Intoi32)
    case wasmSignExtend16Intoi32(WasmSignExtend16Intoi32)
    case wasmSignExtend8Intoi64(WasmSignExtend8Intoi64)
    case wasmSignExtend16Intoi64(WasmSignExtend16Intoi64)
    case wasmSignExtend32Intoi64(WasmSignExtend32Intoi64)
    case wasmTruncateSatf32Toi32(WasmTruncateSatf32Toi32)
    case wasmTruncateSatf64Toi32(WasmTruncateSatf64Toi32)
    case wasmTruncateSatf32Toi64(WasmTruncateSatf32Toi64)
    case wasmTruncateSatf64Toi64(WasmTruncateSatf64Toi64)

    case wasmReassign(WasmReassign)
    case wasmDefineGlobal(WasmDefineGlobal)
    case wasmImportGlobal(WasmImportGlobal)
    case wasmDefineTable(WasmDefineTable)
    case wasmImportTable(WasmImportTable)
    case wasmDefineMemory(WasmDefineMemory)
    case wasmImportMemory(WasmImportMemory)
    case wasmLoadGlobal(WasmLoadGlobal)
    case wasmStoreGlobal(WasmStoreGlobal)
    case wasmTableGet(WasmTableGet)
    case wasmTableSet(WasmTableSet)
    case wasmMemoryGet(WasmMemoryGet)
    case wasmMemorySet(WasmMemorySet)
    case beginWasmFunction(BeginWasmFunction)
    case endWasmFunction(EndWasmFunction)
    case wasmBeginBlock(WasmBeginBlock)
    case wasmEndBlock(WasmEndBlock)
    case wasmBeginLoop(WasmBeginLoop)
    case wasmEndLoop(WasmEndLoop)
    case wasmBranch(WasmBranch)
    case wasmBranchIf(WasmBranchIf)
    case wasmNop(WasmNop)
    case wasmBeginIf(WasmBeginIf)
    case wasmBeginElse(WasmBeginElse)
    case wasmEndIf(WasmEndIf)
}
