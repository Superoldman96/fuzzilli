// Copyright 2019 Google LLC
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

/// Builds programs.
///
/// This provides methods for constructing and appending random
/// instances of the different kinds of operations in a program.
public class ProgramBuilder {
    /// The fuzzer instance for which this builder is active.
    public let fuzzer: Fuzzer

    /// The code and type information of the program that is being constructed.
    private var code = Code()

    /// Comments for the program that is being constructed.
    private var comments = ProgramComments()

    /// Every code generator that contributed to the current program.
    private var contributors = Contributors()

    /// The parent program for the program being constructed.
    private let parent: Program?

    public enum Mode {
        /// In this mode, the builder will try as hard as possible to generate semantically valid code.
        /// However, the generated code is likely not as diverse as in aggressive mode.
        case conservative
        /// In this mode, the builder tries to generate more diverse code. However, the generated
        /// code likely has a lower probability of being semantically correct.
        case aggressive

    }
    /// The mode of this builder
    public var mode: Mode

    public var context: Context {
        return contextAnalyzer.context
    }

    /// Counter to quickly determine the next free variable.
    private var numVariables = 0

    /// Various analyzers for the current program.
    private var variableAnalyzer = VariableAnalyzer()
    private var contextAnalyzer = ContextAnalyzer()

    /// Type inference for JavaScript variables.
    private var jsTyper: JSTyper

    /// Stack of active object literals.
    ///
    /// This needs to be a stack as object literals can be nested, for example if an object
    /// literals is created inside a method/getter/setter of another object literals.
    private var activeObjectLiterals = Stack<ObjectLiteral>()

    /// When building object literals, the state for the current literal is exposed through this member and
    /// can be used to add fields to the literal or to determine if some field already exists.
    public var currentObjectLiteral: ObjectLiteral {
        return activeObjectLiterals.top
    }

    /// Stack of active class definitions.
    ///
    /// Similar to object literals, class definitions can be nested so this needs to be a stack.
    private var activeClassDefinitions = Stack<ClassDefinition>()

    /// When building class definitions, the state for the current definition is exposed through this member and
    /// can be used to add fields to the class or to determine if some field already exists.
    public var currentClassDefinition: ClassDefinition {
        return activeClassDefinitions.top
    }

    /// How many variables are currently in scope.
    public var numberOfVisibleVariables: Int {
        return variableAnalyzer.visibleVariables.count
    }

    /// Whether there are any variables currently in scope.
    public var hasVisibleVariables: Bool {
        return numberOfVisibleVariables > 0
    }

    /// All currently visible variables.
    public var allVisibleVariables: [Variable] {
        return variableAnalyzer.visibleVariables
    }

    /// Constructs a new program builder for the given fuzzer.
    init(for fuzzer: Fuzzer, parent: Program?, mode: Mode) {
        self.fuzzer = fuzzer
        self.jsTyper = JSTyper(for: fuzzer.environment)
        self.mode = mode
        self.parent = parent
    }

    /// Resets this builder.
    public func reset() {
        code.removeAll()
        comments.removeAll()
        contributors.removeAll()
        numVariables = 0
        variableAnalyzer = VariableAnalyzer()
        contextAnalyzer = ContextAnalyzer()
        jsTyper.reset()
        activeObjectLiterals.removeAll()
    }

    /// Finalizes and returns the constructed program, then resets this builder so it can be reused for building another program.
    public func finalize() -> Program {
        assert(openFunctions.isEmpty)
        let program = Program(code: code, parent: parent, comments: comments, contributors: contributors)
        reset()
        return program
    }

    /// Prints the current program as FuzzIL code to stdout. Useful for debugging.
    public func dumpCurrentProgram() {
        print(FuzzILLifter().lift(code))
    }

    /// Returns the current number of instructions of the program we're building.
    public var currentNumberOfInstructions: Int {
        return code.count
    }

    /// Returns the index of the next instruction added to the program. This is equal to the current size of the program.
    public func indexOfNextInstruction() -> Int {
        return currentNumberOfInstructions
    }

    /// Add a trace comment to the currently generated program at the current position.
    /// This is only done if inspection is enabled.
    public func trace(_ commentGenerator: @autoclosure () -> String) {
        if fuzzer.config.enableInspection {
            // Use an autoclosure here so that template strings are only evaluated when they are needed.
            comments.add(commentGenerator(), at: .instruction(code.count))
        }
    }

    /// Add a trace comment at the start of the currently generated program.
    /// This is only done if history inspection is enabled.
    public func traceHeader(_ commentGenerator: @autoclosure () -> String) {
        if fuzzer.config.enableInspection {
            comments.add(commentGenerator(), at: .header)
        }
    }

    ///
    /// Methods to obtain random values to use in a FuzzIL program.
    ///

    /// Returns a random integer value.
    public func randomInt() -> Int64 {
        return withEqualProbability({
            return chooseUniform(from: self.fuzzer.environment.interestingIntegers)
        }, {
            return self.randomSize()
        }, {
            return withEqualProbability({
                Int64.random(in: -0x10...0x10)
            }, {
                Int64.random(in: -0x10000...0x10000)
            }, {
                Int64.random(in: Int64(Int32.min)...Int64(Int32.max))
            })
        })
    }

    /// Returns a random integer value suitable as size of for example an array.
    /// The returned value is guaranteed to be positive.
    public func randomSize() -> Int64 {
        let maxSize: Int64 = 0x100000000
        if probability(0.5) {
            return chooseUniform(from: fuzzer.environment.interestingIntegers.filter({ $0 >= 0 && $0 <= maxSize }))
        } else {
            return withEqualProbability({
                Int64.random(in: 0...0x10)
            }, {
                Int64.random(in: 0...0x100)
            }, {
                Int64.random(in: 0...0x1000)
            }, {
                Int64.random(in: 0...maxSize)
            })
        }
    }

    /// Returns a random integer value suitable as index.
    public func randomIndex() -> Int64 {
        // Prefer small, (usually) positive, indices.
        if probability(0.33) {
            return Int64.random(in: -2...10)
        } else {
            return randomSize()
        }
    }

    /// Returns a random floating point value.
    public func randomFloat() -> Double {
        if probability(0.5) {
            return chooseUniform(from: fuzzer.environment.interestingFloats)
        } else {
            return withEqualProbability({
                Double.random(in: 0.0...1.0)
            }, {
                Double.random(in: -10.0...10.0)
            }, {
                Double.random(in: -1000.0...1000.0)
            }, {
                Double.random(in: -1000000.0...1000000.0)
            }, {
                // We cannot do Double.random(in: -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude) here,
                // presumably because that range is larger than what doubles can represent? So split the range in two.
                if probability(0.5) {
                    return Double.random(in: -Double.greatestFiniteMagnitude...0)
                } else {
                    return Double.random(in: 0...Double.greatestFiniteMagnitude)
                }
            })
        }
    }

    /// Returns a random string value.
    public func randomString() -> String {
        return withEqualProbability({
            self.randomPropertyName()
        }, {
            self.randomMethodName()
        }, {
            chooseUniform(from: self.fuzzer.environment.interestingStrings)
        }, {
            String(self.randomInt())
        }, {
            String.random(ofLength: Int.random(in: 2...10))
        }, {
            String.random(ofLength: 1)
        })
    }

    /// Returns a random regular expression pattern.
    public func randomRegExpPattern() -> String {
        // Generate a "base" regexp
        var regex = ""
        let desiredLength = Int.random(in: 1...4)
        while regex.count < desiredLength {
            regex += withEqualProbability({
                String.random(ofLength: 1)
            }, {
                chooseUniform(from: self.fuzzer.environment.interestingRegExps)
            })
        }

        // Now optionally concatenate with another regexp
        if probability(0.3) {
            regex += randomRegExpPattern()
        }

        // Or add a quantifier, if there is not already a quantifier in the last position.
        if probability(0.2) && !self.fuzzer.environment.interestingRegExpQuantifiers.contains(String(regex.last!)) {
            regex += chooseUniform(from: self.fuzzer.environment.interestingRegExpQuantifiers)
        }

        // Or wrap in brackets
        if probability(0.1) {
            withEqualProbability({
                // optionally invert the character set
                if probability(0.2) {
                    regex = "^" + regex
                }
                regex = "[" + regex + "]"
            }, {
                regex = "(" + regex + ")"
            })
        }
        return regex
    }

    /// Returns the name of a random builtin.
    public func randomBuiltin() -> String {
        return chooseUniform(from: fuzzer.environment.builtins)
    }

    /// Returns a random builtin property name.
    ///
    /// This will return a random name from the environment's list of builtin property names,
    /// i.e. a property that exists on (at least) one builtin object type.
    func randomBuiltinPropertyName() -> String {
        return chooseUniform(from: fuzzer.environment.builtinProperties)
    }

    /// Returns a random custom property name.
    ///
    /// This will select a random property from a (usually relatively small) set of custom property names defined by the environment.
    ///
    /// This should generally be used in one of two situations:
    ///   1. If a new property is added to an object.
    ///     In that case, we prefer to add properties with custom names (e.g. ".a", ".b") instead of properties
    ///     with names that exist in the environment (e.g. ".length", ".prototype"). This way, in the resulting code
    ///     it will be fairly clear when a builtin property is accessed vs. a custom one. It also increases the chances
    ///     of selecting an existing property when choosing a random property to access, see the next point.
    ///   2. If we have no static type information about the object we're accessing.
    ///     In that case there is a higher chance of success when using the small set of custom property names
    ///     instead of the much larger set of all property names that exist in the environment (or something else).
    public func randomCustomPropertyName() -> String {
        return chooseUniform(from: fuzzer.environment.customProperties)
    }

    /// Returns either a builtin or a custom property name, with equal probability.
    public func randomPropertyName() -> String {
        return probability(0.5) ? randomBuiltinPropertyName() : randomCustomPropertyName()
    }

    /// Returns a random builtin method name.
    ///
    /// This will return a random name from the environment's list of builtin method names,
    /// i.e. a method that exists on (at least) one builtin object type.
    public func randomBuiltinMethodName() -> String {
        return chooseUniform(from: fuzzer.environment.builtinMethods)
    }

    /// Returns a random custom method name.
    ///
    /// This will select a random method from a (usually relatively small) set of custom method names defined by the environment.
    ///
    /// See the comment for randomCustomPropertyName() for when this should be used.
    public func randomCustomMethodName() -> String {
        return chooseUniform(from: fuzzer.environment.customMethods)
    }

    /// Returns either a builtin or a custom method name, with equal probability.
    public func randomMethodName() -> String {
        return probability(0.5) ? randomBuiltinMethodName() : randomCustomMethodName()
    }

    // Settings and constants controlling the behavior of randomParameters() below.
    // This determines how many variables of a given type need to be visible before
    // that type is considered a candidate for a parameter type. For example, if this
    // is three, then we need at least three visible .integer variables before creating
    // parameters of type .integer.
    private let thresholdForUseAsParameter = 3

    // The probability of using .anything as parameter type even though we have more specific alternatives.
    // Doing this sometimes is probably beneficial so that completely random values are passed to the function.
    // Future mutations, such as the ExplorationMutator can then figure out what to do with the parameters.
    // Writable so it can be changed for tests.
    var probabilityOfUsingAnythingAsParameterTypeIfAvoidable = 0.20

    // Generate random parameters for a subroutine.
    //
    // This will attempt to find a parameter types for which at least a few variables of a compatible types are
    // currently available to (potentially) later be used as arguments for calling the generated subroutine.
    public func randomParameters(n wantedNumberOfParameters: Int? = nil) -> SubroutineDescriptor {
        assert(probabilityOfUsingAnythingAsParameterTypeIfAvoidable >= 0 && probabilityOfUsingAnythingAsParameterTypeIfAvoidable <= 1)

        // If the caller didn't specify how many parameters to generated, find an appropriate
        // number of parameters based on how many variables are currently visible (and can
        // therefore later be used as arguments for calling the new function).
        let n: Int
        if let requestedN = wantedNumberOfParameters {
            assert(requestedN > 0)
            n = requestedN
        } else {
            switch numberOfVisibleVariables {
            case 0...1:
                n = 0
            case 2...5:
                n = Int.random(in: 1...2)
            default:
                n = Int.random(in: 2...4)
            }
        }

        // Find all types of which we currently have at least a few visible variables that we could later use as arguments.
        // TODO: improve this code by using some kind of cache? That could then also be used for randomVariable(ofType:) etc.
        var availableVariablesByType = [JSType: Int]()
        for v in allVisibleVariables {
            let t = type(of: v)
            // TODO: should we also add this values to the buckets for supertypes (without this becoming O(n^2))?
            // TODO: alternatively just check for some common union types, e.g. .number, .primitive, as long as these can be used meaningfully?
            availableVariablesByType[t] = (availableVariablesByType[t] ?? 0) + 1
        }

        var candidates = Array(availableVariablesByType.filter({ k, v in v >= thresholdForUseAsParameter }).keys)
        if candidates.isEmpty {
            candidates.append(.anything)
        }

        var params = ParameterList()
        for _ in 0..<n {
            if probability(probabilityOfUsingAnythingAsParameterTypeIfAvoidable) {
                params.append(.anything)
            } else {
                params.append(.plain(chooseUniform(from: candidates)))
            }
        }

        // TODO: also generate rest parameters and maybe even optional ones sometimes?

        return .parameters(params)
    }


    ///
    /// Access to variables.
    ///

    /// Returns a random variable.
    public func randomVariable() -> Variable {
        assert(hasVisibleVariables)
        return randomVariableInternal()!
    }

    /// Returns up to N (different) random variables.
    /// This method will only return fewer than N variables if the number of currently visible variables is less than N.
    public func randomVariables(upTo n: Int) -> [Variable] {
        guard hasVisibleVariables else { return [] }

        var variables = [Variable]()
        while variables.count < n {
            guard let newVar = randomVariableInternal(filter: { !variables.contains($0) }) else {
                break
            }
            variables.append(newVar)
        }
        return variables
    }

    /// Returns a random variable to be used as the given type.
    ///
    /// This function may return variables of a different type, or variables that may have the requested type, but could also have a different type.
    /// For example, when requesting a .integer, this function may also return a variable of type .number, .primitive, or even .anything as all of these
    /// types may be an integer (but aren't guaranteed to be). In this way, this function ensures that variables for which no exact type could be statically
    /// determined will also be used as inputs for following code.
    ///
    /// It's the caller's responsibility to check the type of the returned variable to avoid runtime exceptions if necessary. For example, if performing a
    /// property access, the returned variable should be checked if it `MayBe(.nullish)` in which case a property access would result in a
    /// runtime exception and so should be appropriately guarded against that.
    ///
    /// If the variable must be of the specified type, use `randomVariable(ofType:)` instead.
    ///
    /// TODO: consider allowing this function to also return a completely random variable if no MayBe compatible variable is found since the
    /// caller anyway needs to check for compatibility. In practice it probably doesn't matter too much since MayBe already includes .anything.
    public func randomVariable(forUseAs type: JSType) -> Variable? {
        assert(type != .nothing)

        // TODO: we could add some logic here to ensure more diverse variable selection. For example,
        // if there are fewer than N (e.g. 3) visible variables  that satisfy the given constraint
        // (but in total we have more than M, say 10, visible variables) then return nil with a
        // probability of 50% or so and let the caller deal with that appropriately, for example by
        // then picking a random variable and guarding against incorrect types.

        if mode == .aggressive {
            // In aggressive mode return a variable that may have the requested type, but could also
            // have a different type. This way, variables with a union type (e.g. `.number`), and in
            // particular variables of unknown type (i.e. `.anything`) will also be used.
            // TODO: evaluate whether we want to prefer variables for which `.Is(type)` is also true.
            return randomVariableInternal(filter: { self.type(of: $0).MayBe(type) })
        } else {
            // In conservative mode only return variables that are guaranteed to have the correct type.
            return randomVariableInternal(filter: { self.type(of: $0).Is(type) })
        }
    }

    /// Returns a random variable that is known to have the given type.
    ///
    /// This will return a variable for which `b.type(of: v).Is(type)` is true, i.e. for which our type inference
    /// could prove that it will have the specified type. If no such variable is found, this function returns nil.
    public func randomVariable(ofType type: JSType) -> Variable? {
        assert(type != .nothing)
        return randomVariableInternal(filter: { self.type(of: $0).Is(type) })
    }

    /// Returns a random variable satisfying the given constraints or nil if none is found.
    func randomVariableInternal(filter: ((Variable) -> Bool)? = nil) -> Variable? {
        assert(hasVisibleVariables)

        var candidates = [Variable]()

        // Prefer the outputs of the last instruction to build longer data-flow chains.
        if probability(0.15) {
            candidates = Array(code.lastInstruction.allOutputs)
            if let f = filter {
                candidates = candidates.filter(f)
            }
        }

        // Prefer inner scopes if we're not anyway using one of the newest variables.
        let scopes = variableAnalyzer.scopes
        if candidates.isEmpty && probability(0.75) {
            candidates = chooseBiased(from: scopes, factor: 1.25)
            if let f = filter {
                candidates = candidates.filter(f)
            }
        }

        // If we haven't found any candidates yet, take all visible variables into account.
        if candidates.isEmpty {
            let visibleVariables = variableAnalyzer.visibleVariables
            if let f = filter {
                candidates = visibleVariables.filter(f)
            } else {
                candidates = visibleVariables
            }
        }

        if candidates.isEmpty {
            return nil
        }

        return chooseUniform(from: candidates)
    }

    /// Find random variables to use as arguments for calling the specified function.
    ///
    /// This function will attempt to find variables that are compatible with the functions parameter types (if any). However,
    /// if no matching variables can be found for a parameter, this function will fall back to using a random variable. It is
    /// then the caller's responsibility to determine whether the function call can still be performed without raising a runtime
    /// exception or if it needs to be guarded against that.
    /// In this way, functions/methods for which no matching arguments currently exist can still be called (but potentially
    /// wrapped in a try-catch), which then gives future mutations (in particular Mutators such as the ProbingMutator) the
    /// chance to find appropriate arguments for the function.
    public func randomArguments(forCalling function: Variable) -> [Variable] {
        let signature = type(of: function).signature ?? Signature.forUnknownFunction
        return randomArguments(forCallingFunctionOfSignature: signature)
    }

    /// Find random variables to use as arguments for calling the specified method.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingMethod methodName: String, on object: Variable) -> [Variable] {
        let signature = methodSignature(of: methodName, on: object)
        return randomArguments(forCallingFunctionOfSignature: signature)
    }

    /// Find random variables to use as arguments for calling the specified method.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingMethod methodName: String, on objType: JSType) -> [Variable] {
        let signature = methodSignature(of: methodName, on: objType)
        return randomArguments(forCallingFunctionOfSignature: signature)
    }

    /// Find random variables to use as arguments for calling a function with the specified signature.
    ///
    /// See the comment above `randomArguments(forCalling function: Variable)` for caveats.
    public func randomArguments(forCallingFunctionOfSignature signature: Signature) -> [Variable] {
        assert(hasVisibleVariables)
        let parameterTypes = prepareArgumentTypes(forSignature: signature)
        let arguments = parameterTypes.map({ randomVariable(forUseAs: $0) ?? randomVariable() })
        return arguments
    }

    /// Find random arguments for a function call and spread some of them.
    public func randomCallArgumentsWithSpreading(n: Int) -> (arguments: [Variable], spreads: [Bool]) {
        var arguments: [Variable] = []
        var spreads: [Bool] = []
        for _ in 0...n {
            let val = randomVariable()
            arguments.append(val)
            // Prefer to spread values that we know are iterable, as non-iterable values will lead to exceptions ("TypeError: Found non-callable @@iterator")
            if type(of: val).Is(.iterable) {
                spreads.append(probability(0.9))
            } else {
                spreads.append(probability(0.1))
            }
        }

        return (arguments, spreads)
    }


    /// Type information access.
    public func type(of v: Variable) -> JSType {
        return jsTyper.type(of: v)
    }

    /// Returns the type of the `super` binding at the current position.
    public func currentSuperType() -> JSType {
        return jsTyper.currentSuperType()
    }

    /// Returns the type of the super constructor.
    public func currentSuperConstructorType() -> JSType {
        return jsTyper.currentSuperConstructorType()
    }

    public func type(ofProperty property: String, on v: Variable) -> JSType {
        return jsTyper.inferPropertyType(of: property, on: v)
    }

    public func methodSignature(of methodName: String, on object: Variable) -> Signature {
        return jsTyper.inferMethodSignature(of: methodName, on: object)
    }

    public func methodSignature(of methodName: String, on objType: JSType) -> Signature {
        return jsTyper.inferMethodSignature(of: methodName, on: objType)
    }

    /// Overwrite the current type of the given variable with a new type.
    /// This can be useful if a certain code construct is guaranteed to produce a value of a specific type,
    /// but where our static type inference cannot determine that.
    public func setType(ofVariable variable: Variable, to variableType: JSType) {
        jsTyper.setType(of: variable, to: variableType)
    }

    // This expands and collects types for arguments in function signatures.
    private func prepareArgumentTypes(forSignature signature: Signature) -> [JSType] {
        var argumentTypes = [JSType]()

        for param in signature.parameters {
            switch param {
            case .rest(let t):
                // "Unroll" the rest parameter
                for _ in 0..<Int.random(in: 0...5) {
                    argumentTypes.append(t)
                }
            case .opt(let t):
                // It's an optional argument, so stop here in some cases
                if probability(0.25) {
                    return argumentTypes
                }
                fallthrough
            case .plain(let t):
                argumentTypes.append(t)
            }
        }

        return argumentTypes
    }


    ///
    /// Adoption of variables from a different program.
    /// Required when copying instructions between program.
    ///
    private var varMaps = [VariableMap<Variable>]()

    /// Prepare for adoption of variables from the given program.
    ///
    /// This sets up a mapping for variables from the given program to the
    /// currently constructed one to avoid collision of variable names.
    public func beginAdoption(from program: Program) {
        varMaps.append(VariableMap())
    }

    /// Finishes the most recently started adoption.
    public func endAdoption() {
        varMaps.removeLast()
    }

    /// Executes the given block after preparing for adoption from the provided program.
    public func adopting(from program: Program, _ block: () -> Void) {
        beginAdoption(from: program)
        block()
        endAdoption()
    }

    /// Maps a variable from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ variable: Variable) -> Variable {
        if !varMaps.last!.contains(variable) {
            varMaps[varMaps.count - 1][variable] = nextVariable()
        }

        return varMaps.last![variable]!
    }

    /// Maps a list of variables from the program that is currently configured for adoption into the program being constructed.
    public func adopt<Variables: Collection>(_ variables: Variables) -> [Variable] where Variables.Element == Variable {
        return variables.map(adopt)
    }

    /// Adopts an instruction from the program that is currently configured for adoption into the program being constructed.
    public func adopt(_ instr: Instruction) {
        internalAppend(Instruction(instr.op, inouts: adopt(instr.inouts)))
    }

    /// Append an instruction at the current position.
    public func append(_ instr: Instruction) {
        for v in instr.allOutputs {
            numVariables = max(v.number + 1, numVariables)
        }
        internalAppend(instr)
    }

    /// Append a program at the current position.
    ///
    /// This also renames any variable used in the given program so all variables
    /// from the appended program refer to the same values in the current program.
    public func append(_ program: Program) {
        adopting(from: program) {
            for instr in program.code {
                adopt(instr)
            }
        }
    }

    // Probabilities of remapping variables to host variables during splicing. These are writable so they can be reconfigured for testing.
    // We use different probabilities for outer and for inner outputs: while we rarely want to replace outer outputs, we frequently want to replace inner outputs
    // (e.g. function parameters) to avoid splicing function definitions that may then not be used at all. Instead, we prefer to splice only the body of such functions.
    var probabilityOfRemappingAnInstructionsOutputsDuringSplicing = 0.10
    var probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing = 0.75
    // The probability of including an instruction that may mutate a variable required by the slice (but does not itself produce a required variable).
    var probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable = 0.5


    /// Splice code from the given program into the current program.
    ///
    /// Splicing computes a set of dependend (through dataflow) instructions in one program (called a "slice") and inserts it at the current position in this program.
    ///
    /// If the optional index is specified, the slice starting at that instruction is used. Otherwise, a random slice is computed.
    /// If mergeDataFlow is true, the dataflows of the two programs are potentially integrated by replacing some variables in the slice with "compatible" variables in the host program.
    /// Returns true on success (if at least one instruction has been spliced), false otherwise.
    @discardableResult
    public func splice(from program: Program, at specifiedIndex: Int? = nil, mergeDataFlow: Bool = true) -> Bool {
        // Splicing:
        //
        // Invariants:
        //  - A block is included in a slice in full (including its entire body) or not at all
        //  - An instruction can only be included if its required context is a subset of the current context
        //    OR if one or more of its surrounding blocks are included and all missing contexts are opened by them
        //  - An instruction can only be included if all its data-flow dependencies are included
        //    OR if the required variables have been remapped to existing variables in the host program
        //
        // Algorithm:
        //  1. Iterate over the program from start to end and compute for every block:
        //       - the inputs required by this block. This is the set of variables that are used as input
        //         for one or more instructions in the block's body, but are not created by instructions in the block
        //       - the context required by this block. This is the union of all contexts required by instructions
        //         in the block's body and subracting the context opened by the block itself
        //     In essence, this step allows treating every block start as a single instruction, which simplifies step 2.
        //  2. Iterate over the program from start to end and check which instructions can be inserted at the current
        //     position given the current context and the instruction's required context as well as the set of available
        //     variables and the variables required as inputs for the instruction. When deciding whether a block can be
        //     included, this will use the information computed in step 1 to treat the block as a single instruction
        //     (which it effectively is, as it will always be included in full). If an instruction can be included, its
        //     outputs are available for other instructions to use. If an instruction cannot be included, try to remap its
        //     outputs to existing and "compatible" variables in the host program so other instructions that depend on these
        //     variables can still be included. Also randomly remap some other variables to connect the dataflows of the two
        //     programs if that is enabled.
        //  3. Pick a random instruction from all instructions computed in step (2) or use the provided start index.
        //  4. Iterate over the program in reverse order and compute the slice: every instruction that creates an
        //     output needed as input for another instruction in the slice must be included as well. Step 2 guarantees that
        //     any such instruction can be part of the slice. Optionally, this step can also include instructions that may
        //     mutate variables required by the slice, for example property stores or method calls.
        //  5. Iterate over the program from start to end and add every instruction that is part of the slice into
        //     the current program, while also taking care of remapping the inouts, either to existing variables
        //     (if the variables were remapped in step (2)), or newly allocated variables.

        // Helper class to store various bits of information associated with a block.
        // This is a class so that each instruction belonging to the same block can have a reference to the same object.
        class Block {
            let startIndex: Int
            var endIndex = 0

            // Currently opened context. Updated at each block instruction.
            var currentlyOpenedContext: Context
            var requiredContext: Context

            var providedInputs = VariableSet()
            var requiredInputs = VariableSet()

            init(startedBy head: Instruction) {
                self.startIndex = head.index
                self.currentlyOpenedContext = head.op.contextOpened
                self.requiredContext = head.op.requiredContext
                self.requiredInputs.formUnion(head.inputs)
                self.providedInputs.formUnion(head.allOutputs)
            }
        }

        //
        // Step (1): compute the context- and data-flow dependencies of every block.
        //
        var blocks = [Int: Block]()

        // Helper functions for step (1).
        var activeBlocks = [Block]()
        func updateBlockDependencies(_ requiredContext: Context, _ requiredInputs: VariableSet) {
            guard let current = activeBlocks.last else { return }
            current.requiredContext.formUnion(requiredContext.subtracting(current.currentlyOpenedContext))
            current.requiredInputs.formUnion(requiredInputs.subtracting(current.providedInputs))
        }
        func updateBlockProvidedVariables(_ vars: ArraySlice<Variable>) {
            guard let current = activeBlocks.last else { return }
            current.providedInputs.formUnion(vars)
        }

        for instr in program.code {
            updateBlockDependencies(instr.op.requiredContext, VariableSet(instr.inputs))
            updateBlockProvidedVariables(instr.outputs)

            if instr.isBlockGroupStart {
                let block = Block(startedBy: instr)
                blocks[instr.index] = block
                activeBlocks.append(block)
            } else if instr.isBlockGroupEnd {
                let current = activeBlocks.removeLast()
                current.endIndex = instr.index
                blocks[instr.index] = current
                // Merge requirements into parent block (if any)
                updateBlockDependencies(current.requiredContext, current.requiredInputs)
                // If the block end instruction has any outputs, they need to be added to the surrounding block.
                updateBlockProvidedVariables(instr.outputs)
            } else if instr.isBlock {
                // We currently assume that inner block instructions cannot have outputs.
                // If they ever do, they'll need to be added to the surrounding block.
                assert(instr.numOutputs == 0)
                blocks[instr.index] = activeBlocks.last!

                // Inner block instructions change the execution context. Consider BeginWhileLoopBody as an example.
                activeBlocks.last?.currentlyOpenedContext = instr.op.contextOpened
            }

            updateBlockProvidedVariables(instr.innerOutputs)
        }

        //
        // Step (2): determine which instructions can be part of the slice and attempt to find replacement variables for the outputs of instructions that cannot be included.
        //
        // We need a typer to be able to find compatible replacement variables if we are merging the dataflows of the two programs.
        var typer = JSTyper(for: fuzzer.environment)
        // The set of variables that are available for a slice. A variable is available either because the instruction that outputs
        // it can be part of the slice or because the variable has been remapped to a host variable.
        var availableVariables = VariableSet()
        // Variables in the program that have been remapped to host variables.
        var remappedVariables = VariableMap<Variable>()
        // All instructions that can be included in the slice.
        var candidates = Set<Int>()

        // Helper functions for step (2).
        func tryRemapVariables(_ variables: ArraySlice<Variable>, of instr: Instruction) {
            guard mergeDataFlow else { return }
            guard hasVisibleVariables else { return }

            for v in variables {
                let type = typer.type(of: v)
                // For subroutines, the return type is only available once the subroutine has been fully processed.
                // Prior to that, it is assumed to be .anything. This may lead to incompatible functions being selected
                // as replacements (e.g. if the following code assumes that the return value must be of type X), but
                // is probably fine in practice.
                assert(!instr.hasOneOutput || v != instr.output || !(instr.op is BeginAnySubroutine) || (type.signature?.outputType ?? .anything) == .anything)
                // Try to find a compatible variable in the host program.
                if let replacement = randomVariable(forUseAs: type) {
                    remappedVariables[v] = replacement
                    availableVariables.insert(v)
                }
            }
        }
        func maybeRemapVariables(_ variables: ArraySlice<Variable>, of instr: Instruction, withProbability remapProbability: Double) {
            assert(remapProbability >= 0.0 && remapProbability <= 1.0)
            if probability(remapProbability) {
                tryRemapVariables(variables, of: instr)
            }
        }
        func getRequirements(of instr: Instruction) -> (requiredContext: Context, requiredInputs: VariableSet) {
            if let state = blocks[instr.index] {
                assert(instr.isBlock)
                return (state.requiredContext, state.requiredInputs)
            } else {
                return (instr.op.requiredContext, VariableSet(instr.inputs))
            }
        }
        func canSpliceOperation(of instr: Instruction) -> Bool {
            // Switch default cases cannot be spliced as there must only be one of them in a switch, and there is no
            // way to determine if the switch being spliced into has a default case or not.
            // TODO: consider adding an Operation.Attribute for instructions that must only occur once if there are more such cases in the future.
            var instr = instr
            if let block = blocks[instr.index] {
                instr = program.code[block.startIndex]
            }
            if instr.op is BeginSwitchDefaultCase {
                return false
            }
            return true
        }

        for instr in program.code {
            // Compute variable types to be able to find compatible replacement variables in the host program if necessary.
            typer.analyze(instr)

            // Maybe remap the outputs of this instruction to existing and "compatible" (because of their type) variables in the host program.
            maybeRemapVariables(instr.outputs, of: instr, withProbability: probabilityOfRemappingAnInstructionsOutputsDuringSplicing)
            maybeRemapVariables(instr.innerOutputs, of: instr, withProbability: probabilityOfRemappingAnInstructionsInnerOutputsDuringSplicing)

            // For the purpose of this step, blocks are treated as a single instruction with all the context and input requirements of the
            // instructions in their body. This is done through the getRequirements function which uses the data computed in step (1).
            let (requiredContext, requiredInputs) = getRequirements(of: instr)

            if requiredContext.isSubset(of: context) && requiredInputs.isSubset(of: availableVariables) && canSpliceOperation(of: instr) {
                candidates.insert(instr.index)
                // This instruction is available, and so are its outputs...
                availableVariables.formUnion(instr.allOutputs)
            } else {
                // While we cannot include this instruction, we may still be able to replace its outputs with existing variables in the host program
                // which will allow other instructions that depend on these outputs to be included.
                tryRemapVariables(instr.allOutputs, of: instr)
            }
        }

        //
        // Step (3): select the "root" instruction of the slice or use the provided one if any.
        //
        // Simple optimization: avoid splicing data-flow "roots", i.e. simple instructions that don't have any inputs, as this will
        // most of the time result in fairly uninteresting splices that for example just copy a literal from another program.
        // The exception to this are special instructions that exist outside of JavaScript context, for example instructions that add fields to classes.
        let rootCandidates = candidates.filter({ !program.code[$0].isSimple || program.code[$0].numInputs > 0 || !program.code[$0].op.requiredContext.contains(.javascript) })
        guard !rootCandidates.isEmpty else { return false }
        let rootIndex = specifiedIndex ?? chooseUniform(from: rootCandidates)
        guard rootCandidates.contains(rootIndex) else { return false }
        trace("Splicing instruction \(rootIndex) (\(program.code[rootIndex].op.name)) from \(program.id)")

        //
        // Step (4): compute the slice.
        //
        var slice = Set<Int>()
        var requiredVariables = VariableSet()
        var shouldIncludeCurrentBlock = false
        var startOfCurrentBlock = -1
        var index = rootIndex
        while index >= 0 {
            let instr = program.code[index]

            var includeCurrentInstruction = false
            if index == rootIndex {
                // This is the root of the slice, so include it.
                includeCurrentInstruction = true
                assert(candidates.contains(index))
            } else if shouldIncludeCurrentBlock {
                // This instruction is part of the slice because one of its surrounding blocks is included.
                includeCurrentInstruction = true
                // In this case, the instruction isn't necessarily a candidate (but at least one of its surrounding blocks is).
            } else if !requiredVariables.isDisjoint(with: instr.allOutputs) {
                // This instruction is part of the slice because at least one of its outputs is required.
                includeCurrentInstruction = true
                assert(candidates.contains(index))
            } else {
                // Also (potentially) include instructions that can modify one of the required variables if they can be included in the slice.
                if probability(probabilityOfIncludingAnInstructionThatMayMutateARequiredVariable) {
                    if candidates.contains(index) && instr.mayMutate(anyOf: requiredVariables) {
                        includeCurrentInstruction = true
                    }
                }
            }

            if includeCurrentInstruction {
                slice.insert(instr.index)

                // Only those inputs that we haven't picked replacements for are now also required.
                let newlyRequiredVariables = instr.inputs.filter({ !remappedVariables.contains($0) })
                requiredVariables.formUnion(newlyRequiredVariables)

                if !shouldIncludeCurrentBlock && instr.isBlock {
                    // We're including a block instruction due to its outputs. We now need to ensure that we include the full block with it.
                    shouldIncludeCurrentBlock = true
                    let block = blocks[index]!
                    startOfCurrentBlock = block.startIndex
                    index = block.endIndex + 1
                }
            }

            if index == startOfCurrentBlock {
                assert(instr.isBlockGroupStart)
                shouldIncludeCurrentBlock = false
                startOfCurrentBlock = -1
            }

            index -= 1
        }

        //
        // Step (5): insert the final slice into the current program while also remapping any missing variables to their replacements selected in step (2).
        //
        var variableMap = remappedVariables
        for instr in program.code where slice.contains(instr.index) {
            for output in instr.allOutputs {
                variableMap[output] = nextVariable()
            }
            let inouts = instr.inouts.map({ variableMap[$0]! })
            append(Instruction(instr.op, inouts: inouts))
        }

        trace("Splicing done")
        return true
    }

    // Code Building Algorithm:
    //
    // In theory, the basic building algorithm is simply:
    //
    //   var remainingBudget = initialBudget
    //   while remainingBudget > 0 {
    //       if probability(0.5) {
    //           remainingBudget -= runRandomCodeGenerator()
    //       } else {
    //           remainingBudget -= performSplicing()
    //       }
    //   }
    //
    // In practice, things become a little more complicated because code generators can be recursive: a function
    // generator will emit the function start and end and recursively call into the code building machinery to fill the
    // body of the function. The size of the recursively generated blocks is determined as a fraction of the parent's
    // *initial budget*. This ensures that the sizes of recursively generated blocks roughly follow the same
    // distribution. However, it also means that the initial budget can be overshot by quite a bit: we may end up
    // invoking a recursive generator near the end of our budget, which may then for example generate another 0.5x
    // initialBudget instructions. However, the benefit of this approach is that there are really only two "knobs" that
    // determine the "shape" of the generated code: the factor that determines the recursive budget relative to the
    // parent budget and the (absolute) threshold for recursive code generation.
    //

    /// The first "knob": this mainly determines the shape of generated code as it determines how large block bodies are relative to their surrounding code.
    /// This also influences the nesting depth of the generated code, as recursive code generators are only invoked if enough "budget" is still available.
    /// These are writable so they can be reconfigured in tests.
    var minRecursiveBudgetRelativeToParentBudget = 0.05
    var maxRecursiveBudgetRelativeToParentBudget = 0.50

    /// The second "knob": the minimum budget required to be able to invoke recursive code generators.
    public static let minBudgetForRecursiveCodeGeneration = 5

    /// Possible building modes. These are used as argument for build() and determine how the new code is produced.
    public enum BuildingMode {
        // Generate code by running CodeGenerators.
        case generating
        // Splice code from other random programs in the corpus.
        case splicing
        // Do all of the above.
        case generatingAndSplicing
    }

    private var openFunctions = [Variable]()
    private func callLikelyRecurses(function: Variable) -> Bool {
        return openFunctions.contains(function)
    }

    // Keeps track of the state of one buildInternal() invocation. These are tracked in a stack, one entry for each recursive call.
    // This is a class so that updating the currently active state is possible without push/pop.
    private class BuildingState {
        let initialBudget: Int
        let mode: BuildingMode
        var recursiveBuildingAllowed = true
        var nextRecursiveBlockOfCurrentGenerator = 1
        var totalRecursiveBlocksOfCurrentGenerator: Int? = nil

        init(initialBudget: Int, mode: BuildingMode) {
            assert(initialBudget > 0)
            self.initialBudget = initialBudget
            self.mode = mode
        }
    }
    private var buildStack = Stack<BuildingState>()

    /// Build random code at the current position in the program.
    ///
    /// The first parameter controls the number of emitted instructions: as soon as more than that number of instructions have been emitted, building stops.
    /// This parameter is only a rough estimate as recursive code generators may lead to significantly more code being generated.
    /// Typically, the actual number of generated instructions will be somewhere between n and 2x n.
    ///
    /// Building code requires that there are visible variables available as inputs for CodeGenerators or as replacement variables for splicing.
    /// When building new programs, `buildPrefix()` can be used to generate some initial variables. `build()` purposely does not call
    /// `buildPrefix()` itself so that the budget isn't accidentally spent just on prefix code (which is probably less interesting).
    public func build(n: Int = 1, by mode: BuildingMode = .generatingAndSplicing) {
        assert(buildStack.isEmpty)
        buildInternal(initialBuildingBudget: n, mode: mode)
        assert(buildStack.isEmpty)
    }

    /// Recursive code building. Used by CodeGenerators for example to fill the bodies of generated blocks.
    public func buildRecursive(block: Int = 1, of numBlocks: Int = 1, n optionalBudget: Int? = nil) {
        assert(!buildStack.isEmpty)
        let parentState = buildStack.top

        assert(parentState.mode != .splicing)
        assert(parentState.recursiveBuildingAllowed)        // If this fails, a recursive CodeGenerator is probably not marked as recursive.
        assert(numBlocks >= 1)
        assert(block >= 1 && block <= numBlocks)
        assert(parentState.nextRecursiveBlockOfCurrentGenerator == block)
        assert((parentState.totalRecursiveBlocksOfCurrentGenerator ?? numBlocks) == numBlocks)

        parentState.nextRecursiveBlockOfCurrentGenerator = block + 1
        parentState.totalRecursiveBlocksOfCurrentGenerator = numBlocks

        // Determine the budget for this recursive call as a fraction of the parent's initial budget.
        let factor = Double.random(in: minRecursiveBudgetRelativeToParentBudget...maxRecursiveBudgetRelativeToParentBudget)
        assert(factor > 0.0 && factor < 1.0)
        let parentBudget = parentState.initialBudget
        var recursiveBudget = Double(parentBudget) * factor

        // Now split the budget between all sibling blocks.
        recursiveBudget /= Double(numBlocks)
        recursiveBudget.round(.up)
        assert(recursiveBudget >= 1.0)

        // Finally, if a custom budget was requested, choose the smaller of the two values.
        if let requestedBudget = optionalBudget {
            assert(requestedBudget > 0)
            recursiveBudget = min(recursiveBudget, Double(requestedBudget))
        }

        buildInternal(initialBuildingBudget: Int(recursiveBudget), mode: parentState.mode)
    }

    private func buildInternal(initialBuildingBudget: Int, mode: BuildingMode) {
        assert(hasVisibleVariables, "CodeGenerators and our splicing implementation assume that there are visible variables to use. Use buildPrefix() to generate some initial variables in a new program")
        assert(initialBuildingBudget > 0)

        // Both splicing and code generation can sometimes fail, for example if no other program with the necessary features exists.
        // To avoid infinite loops, we bail out after a certain number of consecutive failures.
        var consecutiveFailures = 0

        let state = BuildingState(initialBudget: initialBuildingBudget, mode: mode)
        buildStack.push(state)
        defer { buildStack.pop() }
        var remainingBudget = initialBuildingBudget

        // Unless we are only splicing, find all generators that have the required context. We must always have at least one suitable code generator.
        let origContext = context
        var availableGenerators = WeightedList<CodeGenerator>()
        if state.mode != .splicing {
            availableGenerators = fuzzer.codeGenerators.filter({ $0.requiredContext.isSubset(of: origContext) })
            assert(!availableGenerators.isEmpty)
        }

        while remainingBudget > 0 {
            assert(context == origContext, "Code generation or splicing must not change the current context")

            if state.recursiveBuildingAllowed &&
                remainingBudget < ProgramBuilder.minBudgetForRecursiveCodeGeneration &&
                availableGenerators.contains(where: { !$0.isRecursive }) {
                // No more recursion at this point since the remaining budget is too small.
                state.recursiveBuildingAllowed = false
                availableGenerators = availableGenerators.filter({ !$0.isRecursive })
                assert(state.mode == .splicing || !availableGenerators.isEmpty)
            }

            var mode = state.mode
            if mode == .generatingAndSplicing {
                mode = chooseUniform(from: [.generating, .splicing])
            }

            let codeSizeBefore = code.count
            switch mode {
            case .generating:
                assert(hasVisibleVariables)

                // Reset the code generator specific part of the state.
                state.nextRecursiveBlockOfCurrentGenerator = 1
                state.totalRecursiveBlocksOfCurrentGenerator = nil

                // Select a random generator and run it.
                let generator = availableGenerators.randomElement()
                run(generator)

            case .splicing:
                let program = fuzzer.corpus.randomElementForSplicing()
                splice(from: program)

            default:
                fatalError("Unknown ProgramBuildingMode \(mode)")
            }
            let codeSizeAfter = code.count

            let emittedInstructions = codeSizeAfter - codeSizeBefore
            remainingBudget -= emittedInstructions
            if emittedInstructions > 0 {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                guard consecutiveFailures < 10 else {
                    // This should happen very rarely, for example if we're splicing into a restricted context and don't find
                    // another sample with instructions that can be copied over, or if we get very unlucky with the code generators.
                    return
                }
            }
        }
    }

    /// Run ValueGenerators until we have created at least N new variables.
    /// Returns both the number of generated instructions and of newly created variables.
    @discardableResult
    public func buildValues(_ n: Int) -> (generatedInstructions: Int, generatedVariables: Int) {
        assert(context.contains(.javascript))
        let valueGenerators = fuzzer.codeGenerators.filter({ $0.isValueGenerator })
        assert(!valueGenerators.isEmpty)
        let previousNumberOfVisibleVariables = numberOfVisibleVariables
        var totalNumberOfGeneratedInstructions = 0
        while numberOfVisibleVariables - previousNumberOfVisibleVariables < n {
            let generator = valueGenerators.randomElement()
            assert(generator.requiredContext == .javascript && generator.inputTypes.isEmpty)
            let numberOfGeneratedInstructions = run(generator)
            assert(numberOfGeneratedInstructions > 0, "ValueGenerators must always succeed")
            totalNumberOfGeneratedInstructions += numberOfGeneratedInstructions
        }
        return (totalNumberOfGeneratedInstructions, numberOfVisibleVariables - previousNumberOfVisibleVariables)
    }

    /// Bootstrap program building by creating some variables with statically known types.
    ///
    /// The `build()` method for generating new code or splicing from existing code can
    /// only be used once there are visible variables. This method can be used to generate some.
    ///
    /// Internally, this uses the ValueGenerators to generate some code. As such, the "shape"
    /// of prefix code is controlled in the same way as other generated code through the
    /// generator's respective weights.
    public func buildPrefix() {
        buildValues(Int.random(in: 5...10))
    }

    /// Runs a code generator in the current context and returns the number of generated instructions.
    @discardableResult
    public func run(_ generator: CodeGenerator) -> Int {
        assert(generator.requiredContext.isSubset(of: context))

        var inputs: [Variable] = []
        for type in generator.inputTypes {
            guard let val = randomVariable(forUseAs: type) else { return 0 }
            // In conservative mode, attempt to prevent direct recursion to reduce the number of timeouts
            // This is a very crude mechanism. It might be worth implementing a more sophisticated one.
            if mode == .conservative && type.Is(.function()) && callLikelyRecurses(function: val) { return 0 }

            inputs.append(val)
        }

        trace("Executing code generator \(generator.name)")
        let numGeneratedInstructions = generator.run(in: self, with: inputs)
        trace("Code generator finished")

        if numGeneratedInstructions > 0 {
            contributors.insert(generator)
            generator.addedInstructions(numGeneratedInstructions)
        }
        return numGeneratedInstructions
    }

    //
    // Low-level instruction constructors.
    //
    // These create an instruction with the provided values and append it to the program at the current position.
    // If the instruction produces a new variable, that variable is returned to the caller.
    // Each class implementing the Operation protocol will have a constructor here.
    //

    @discardableResult
    private func emit(_ op: Operation, withInputs inputs: [Variable] = []) -> Instruction {
        var inouts = inputs
        for _ in 0..<op.numOutputs {
            inouts.append(nextVariable())
        }
        for _ in 0..<op.numInnerOutputs {
            inouts.append(nextVariable())
        }

        return internalAppend(Instruction(op, inouts: inouts))
    }

    @discardableResult
    public func loadInt(_ value: Int64) -> Variable {
        return emit(LoadInteger(value: value)).output
    }

    @discardableResult
    public func loadBigInt(_ value: Int64) -> Variable {
        return emit(LoadBigInt(value: value)).output
    }

    @discardableResult
    public func loadFloat(_ value: Double) -> Variable {
        return emit(LoadFloat(value: value)).output
    }

    @discardableResult
    public func loadString(_ value: String) -> Variable {
        return emit(LoadString(value: value)).output
    }

    @discardableResult
    public func loadBool(_ value: Bool) -> Variable {
        return emit(LoadBoolean(value: value)).output
    }

    @discardableResult
    public func loadUndefined() -> Variable {
        return emit(LoadUndefined()).output
    }

    @discardableResult
    public func loadNull() -> Variable {
        return emit(LoadNull()).output
    }

    @discardableResult
    public func loadThis() -> Variable {
        return emit(LoadThis()).output
    }

    @discardableResult
    public func loadArguments() -> Variable {
        return emit(LoadArguments()).output
    }

    @discardableResult
    public func loadRegExp(_ pattern: String, _ flags: RegExpFlags) -> Variable {
        return emit(LoadRegExp(pattern: pattern, flags: flags)).output
    }

    /// Represents a currently active object literal. Used to add fields to it and to query which fields already exist.
    public class ObjectLiteral {
        private let b: ProgramBuilder

        fileprivate var existingProperties: [String] = []
        fileprivate var existingElements: [Int64] = []
        fileprivate var existingComputedProperties: [Variable] = []
        fileprivate var existingMethods: [String] = []
        fileprivate var existingComputedMethods: [Variable] = []
        fileprivate var existingGetters: [String] = []
        fileprivate var existingSetters: [String] = []

        public fileprivate(set) var hasPrototype = false

        fileprivate init(in b: ProgramBuilder) {
            assert(b.context.contains(.objectLiteral))
            self.b = b
        }

        public func hasProperty(_ name: String) -> Bool {
            return existingProperties.contains(name)
        }

        public func hasElement(_ index: Int64) -> Bool {
            return existingElements.contains(index)
        }

        public func hasComputedProperty(_ name: Variable) -> Bool {
            return existingComputedProperties.contains(name)
        }

        public func hasMethod(_ name: String) -> Bool {
            return existingMethods.contains(name)
        }

        public func hasComputedMethod(_ name: Variable) -> Bool {
            return existingComputedMethods.contains(name)
        }

        public func hasGetter(for name: String) -> Bool {
            return existingGetters.contains(name)
        }

        public func hasSetter(for name: String) -> Bool {
            return existingSetters.contains(name)
        }

        public func addProperty(_ name: String, as value: Variable) {
            b.emit(ObjectLiteralAddProperty(propertyName: name), withInputs: [value])
        }

        public func addElement(_ index: Int64, as value: Variable) {
            b.emit(ObjectLiteralAddElement(index: index), withInputs: [value])
        }

        public func addComputedProperty(_ name: Variable, as value: Variable) {
            b.emit(ObjectLiteralAddComputedProperty(), withInputs: [name, value])
        }

        public func copyProperties(from obj: Variable) {
            b.emit(ObjectLiteralCopyProperties(), withInputs: [obj])
        }

        public func setPrototype(to proto: Variable) {
            b.emit(ObjectLiteralSetPrototype(), withInputs: [proto])
        }

        public func addMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginObjectLiteralMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndObjectLiteralMethod())
        }

        public func addComputedMethod(_ name: Variable, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginObjectLiteralComputedMethod(parameters: descriptor.parameters), withInputs: [name])
            body(Array(instr.innerOutputs))
            b.emit(EndObjectLiteralComputedMethod())
        }

        public func addGetter(for name: String, _ body: (_ this: Variable) -> ()) {
            let instr = b.emit(BeginObjectLiteralGetter(propertyName: name))
            body(instr.innerOutput)
            b.emit(EndObjectLiteralGetter())
        }

        public func addSetter(for name: String, _ body: (_ this: Variable, _ val: Variable) -> ()) {
            let instr = b.emit(BeginObjectLiteralSetter(propertyName: name))
            body(instr.innerOutput(0), instr.innerOutput(1))
            b.emit(EndObjectLiteralSetter())
        }
    }

    @discardableResult
    public func buildObjectLiteral(_ body: (ObjectLiteral) -> ()) -> Variable {
        emit(BeginObjectLiteral())
        body(currentObjectLiteral)
        return emit(EndObjectLiteral()).output
    }

    @discardableResult
    // Convenience method to create simple object literals.
    public func createObject(with initialProperties: [String: Variable]) -> Variable {
        return buildObjectLiteral { obj in
            // Sort the property names so that the emitted code is deterministic.
            for (propertyName, value) in initialProperties.sorted(by: { $0.key < $1.key }) {
                obj.addProperty(propertyName, as: value)
            }
        }
    }

    /// Represents a currently active class definition. Used to add fields to it and to query which fields already exist.
    public class ClassDefinition {
        private let b: ProgramBuilder

        public let isDerivedClass: Bool

        public fileprivate(set) var hasConstructor = false
        fileprivate var existingInstanceProperties: [String] = []
        fileprivate var existingInstanceElements: [Int64] = []
        fileprivate var existingInstanceComputedProperties: [Variable] = []
        fileprivate var existingInstanceMethods: [String] = []
        fileprivate var existingInstanceGetters: [String] = []
        fileprivate var existingInstanceSetters: [String] = []

        fileprivate var existingStaticProperties: [String] = []
        fileprivate var existingStaticElements: [Int64] = []
        fileprivate var existingStaticComputedProperties: [Variable] = []
        fileprivate var existingStaticMethods: [String] = []
        fileprivate var existingStaticGetters: [String] = []
        fileprivate var existingStaticSetters: [String] = []

        // These sets are (read-only) exposed as they are required to ensure syntactic correctness:
        // In JavaScript, it is a syntax error to access a private property/method that has not
        // been declared by the surrounding class. Further, each private field must only be declared
        // once, regardless of whether it is a method or a property and whether it's per-instance of
        // static. However, we still track properties and methods separately to facilitate selecting
        // property and method names for private property accesses and private method calls.
        public fileprivate(set) var existingPrivateProperties: [String] = []
        public fileprivate(set) var existingPrivateMethods: [String] = []

        fileprivate init(in b: ProgramBuilder, isDerived: Bool) {
            assert(b.context.contains(.classDefinition))
            self.b = b
            self.isDerivedClass = isDerived
        }

        public func hasInstanceProperty(_ name: String) -> Bool {
            return existingInstanceProperties.contains(name)
        }

        public func hasInstanceElement(_ index: Int64) -> Bool {
            return existingInstanceElements.contains(index)
        }

        public func hasInstanceComputedProperty(_ v: Variable) -> Bool {
            return existingInstanceComputedProperties.contains(v)
        }

        public func hasInstanceMethod(_ name: String) -> Bool {
            return existingInstanceMethods.contains(name)
        }

        public func hasInstanceGetter(for name: String) -> Bool {
            return existingInstanceGetters.contains(name)
        }

        public func hasInstanceSetter(for name: String) -> Bool {
            return existingInstanceSetters.contains(name)
        }

        public func hasStaticProperty(_ name: String) -> Bool {
            return existingStaticProperties.contains(name)
        }

        public func hasStaticElement(_ index: Int64) -> Bool {
            return existingStaticElements.contains(index)
        }

        public func hasStaticComputedProperty(_ v: Variable) -> Bool {
            return existingStaticComputedProperties.contains(v)
        }

        public func hasStaticMethod(_ name: String) -> Bool {
            return existingStaticMethods.contains(name)
        }

        public func hasStaticGetter(for name: String) -> Bool {
            return existingStaticGetters.contains(name)
        }

        public func hasStaticSetter(for name: String) -> Bool {
            return existingStaticSetters.contains(name)
        }

        public func hasPrivateProperty(_ name: String) -> Bool {
            return existingPrivateProperties.contains(name)
        }

        public func hasPrivateMethod(_ name: String) -> Bool {
            return existingPrivateMethods.contains(name)
        }

        public func hasPrivateField(_ name: String) -> Bool {
            return hasPrivateProperty(name) || hasPrivateMethod(name)
        }

        public func addConstructor(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassConstructor(parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassConstructor())
        }

        public func addInstanceProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddInstanceProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addInstanceElement(_ index: Int64, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddInstanceElement(index: index, hasValue: value != nil), withInputs: inputs)
        }

        public func addInstanceComputedProperty(_ name: Variable, value: Variable? = nil) {
            let inputs = value != nil ? [name, value!] : [name]
            b.emit(ClassAddInstanceComputedProperty(hasValue: value != nil), withInputs: inputs)
        }

        public func addInstanceMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassInstanceMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassInstanceMethod())
        }

        public func addInstanceGetter(for name: String, _ body: (_ this: Variable) -> ()) {
            let instr = b.emit(BeginClassInstanceGetter(propertyName: name))
            body(instr.innerOutput)
            b.emit(EndClassInstanceGetter())
        }

        public func addInstanceSetter(for name: String, _ body: (_ this: Variable, _ val: Variable) -> ()) {
            let instr = b.emit(BeginClassInstanceSetter(propertyName: name))
            body(instr.innerOutput(0), instr.innerOutput(1))
            b.emit(EndClassInstanceSetter())
        }

        public func addStaticProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddStaticProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addStaticElement(_ index: Int64, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddStaticElement(index: index, hasValue: value != nil), withInputs: inputs)
        }

        public func addStaticComputedProperty(_ name: Variable, value: Variable? = nil) {
            let inputs = value != nil ? [name, value!] : [name]
            b.emit(ClassAddStaticComputedProperty(hasValue: value != nil), withInputs: inputs)
        }

        public func addStaticInitializer(_ body: (Variable) -> ()) {
            let instr = b.emit(BeginClassStaticInitializer())
            body(instr.innerOutput)
            b.emit(EndClassStaticInitializer())
        }

        public func addStaticMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassStaticMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassStaticMethod())
        }

        public func addStaticGetter(for name: String, _ body: (_ this: Variable) -> ()) {
            let instr = b.emit(BeginClassStaticGetter(propertyName: name))
            body(instr.innerOutput)
            b.emit(EndClassStaticGetter())
        }

        public func addStaticSetter(for name: String, _ body: (_ this: Variable, _ val: Variable) -> ()) {
            let instr = b.emit(BeginClassStaticSetter(propertyName: name))
            body(instr.innerOutput(0), instr.innerOutput(1))
            b.emit(EndClassStaticSetter())
        }

        public func addPrivateInstanceProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddPrivateInstanceProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addPrivateInstanceMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassPrivateInstanceMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassPrivateInstanceMethod())
        }

        public func addPrivateStaticProperty(_ name: String, value: Variable? = nil) {
            let inputs = value != nil ? [value!] : []
            b.emit(ClassAddPrivateStaticProperty(propertyName: name, hasValue: value != nil), withInputs: inputs)
        }

        public func addPrivateStaticMethod(_ name: String, with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) {
            b.setParameterTypesForNextSubroutine(descriptor.parameterTypes)
            let instr = b.emit(BeginClassPrivateStaticMethod(methodName: name, parameters: descriptor.parameters))
            body(Array(instr.innerOutputs))
            b.emit(EndClassPrivateStaticMethod())
        }
    }

    @discardableResult
    public func buildClassDefinition(withSuperclass superclass: Variable? = nil, _ body: (ClassDefinition) -> ()) -> Variable {
        let inputs = superclass != nil ? [superclass!] : []
        let output = emit(BeginClassDefinition(hasSuperclass: superclass != nil), withInputs: inputs).output
        body(currentClassDefinition)
        emit(EndClassDefinition())
        return output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable]) -> Variable {
        return emit(CreateArray(numInitialValues: initialValues.count), withInputs: initialValues).output
    }

    @discardableResult
    public func createIntArray(with initialValues: [Int64]) -> Variable {
        return emit(CreateIntArray(values: initialValues)).output
    }

    @discardableResult
    public func createFloatArray(with initialValues: [Double]) -> Variable {
        return emit(CreateFloatArray(values: initialValues)).output
    }

    @discardableResult
    public func createArray(with initialValues: [Variable], spreading spreads: [Bool]) -> Variable {
        assert(initialValues.count == spreads.count)
        return emit(CreateArrayWithSpread(spreads: spreads), withInputs: initialValues).output
    }

    @discardableResult
    public func createTemplateString(from parts: [String], interpolating interpolatedValues: [Variable]) -> Variable {
        return emit(CreateTemplateString(parts: parts), withInputs: interpolatedValues).output
    }

    @discardableResult
    public func loadBuiltin(_ name: String) -> Variable {
        return emit(LoadBuiltin(builtinName: name)).output
    }

    @discardableResult
    public func getProperty(_ name: String, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        return emit(GetProperty(propertyName: name, isGuarded: isGuarded), withInputs: [object]).output
    }

    public func setProperty(_ name: String, of object: Variable, to value: Variable) {
        emit(SetProperty(propertyName: name), withInputs: [object, value])
    }

    public func updateProperty(_ name: String, of object: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdateProperty(propertyName: name, operator: op), withInputs: [object, value])
    }

    @discardableResult
    public func deleteProperty(_ name: String, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        emit(DeleteProperty(propertyName: name, isGuarded: isGuarded), withInputs: [object]).output
    }

    public enum PropertyConfiguration {
        case value(Variable)
        case getter(Variable)
        case setter(Variable)
        case getterSetter(Variable, Variable)
    }

    public func configureProperty(_ name: String, of object: Variable, usingFlags flags: PropertyFlags, as config: PropertyConfiguration) {
        switch config {
        case .value(let value):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .value), withInputs: [object, value])
        case .getter(let getter):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .getter), withInputs: [object, getter])
        case .setter(let setter):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .setter), withInputs: [object, setter])
        case .getterSetter(let getter, let setter):
            emit(ConfigureProperty(propertyName: name, flags: flags, type: .getterSetter), withInputs: [object, getter, setter])
        }
    }

    @discardableResult
    public func getElement(_ index: Int64, of array: Variable, guard isGuarded: Bool = false) -> Variable {
        return emit(GetElement(index: index, isGuarded: isGuarded), withInputs: [array]).output
    }

    public func setElement(_ index: Int64, of array: Variable, to value: Variable) {
        emit(SetElement(index: index), withInputs: [array, value])
    }

    public func updateElement(_ index: Int64, of array: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdateElement(index: index, operator: op), withInputs: [array, value])
    }

    @discardableResult
    public func deleteElement(_ index: Int64, of array: Variable, guard isGuarded: Bool = false) -> Variable {
        emit(DeleteElement(index: index, isGuarded: isGuarded), withInputs: [array]).output
    }

    public func configureElement(_ index: Int64, of object: Variable, usingFlags flags: PropertyFlags, as config: PropertyConfiguration) {
        switch config {
        case .value(let value):
            emit(ConfigureElement(index: index, flags: flags, type: .value), withInputs: [object, value])
        case .getter(let getter):
            emit(ConfigureElement(index: index, flags: flags, type: .getter), withInputs: [object, getter])
        case .setter(let setter):
            emit(ConfigureElement(index: index, flags: flags, type: .setter), withInputs: [object, setter])
        case .getterSetter(let getter, let setter):
            emit(ConfigureElement(index: index, flags: flags, type: .getterSetter), withInputs: [object, getter, setter])
        }
    }

    @discardableResult
    public func getComputedProperty(_ name: Variable, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        return emit(GetComputedProperty(isGuarded: isGuarded), withInputs: [object, name]).output
    }

    public func setComputedProperty(_ name: Variable, of object: Variable, to value: Variable) {
        emit(SetComputedProperty(), withInputs: [object, name, value])
    }

    public func updateComputedProperty(_ name: Variable, of object: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdateComputedProperty(operator: op), withInputs: [object, name, value])
    }

    @discardableResult
    public func deleteComputedProperty(_ name: Variable, of object: Variable, guard isGuarded: Bool = false) -> Variable {
        emit(DeleteComputedProperty(isGuarded: isGuarded), withInputs: [object, name]).output
    }

    public func configureComputedProperty(_ name: Variable, of object: Variable, usingFlags flags: PropertyFlags, as config: PropertyConfiguration) {
        switch config {
        case .value(let value):
            emit(ConfigureComputedProperty(flags: flags, type: .value), withInputs: [object, name, value])
        case .getter(let getter):
            emit(ConfigureComputedProperty(flags: flags, type: .getter), withInputs: [object, name, getter])
        case .setter(let setter):
            emit(ConfigureComputedProperty(flags: flags, type: .setter), withInputs: [object, name, setter])
        case .getterSetter(let getter, let setter):
            emit(ConfigureComputedProperty(flags: flags, type: .getterSetter), withInputs: [object, name, getter, setter])
        }
    }

    @discardableResult
    public func typeof(_ v: Variable) -> Variable {
        return emit(TypeOf(), withInputs: [v]).output
    }

    @discardableResult
    public func testInstanceOf(_ v: Variable, _ type: Variable) -> Variable {
        return emit(TestInstanceOf(), withInputs: [v, type]).output
    }

    @discardableResult
    public func testIn(_ prop: Variable, _ obj: Variable) -> Variable {
        return emit(TestIn(), withInputs: [prop, obj]).output
    }

    public func explore(_ v: Variable, id: String, withArgs arguments: [Variable]) {
        emit(Explore(id: id, numArguments: arguments.count), withInputs: [v] + arguments)
    }

    public func probe(_ v: Variable, id: String) {
        emit(Probe(id: id), withInputs: [v])
    }

    // Helper struct to describe subroutine definitions.
    // This allows defining functions by just specifying the number of parameters or by specifying the types of the individual parameters.
    // Note however that parameter types are not associated with the generated operations and will therefore just be valid for the lifetime
    // of this ProgramBuilder. The reason for this behaviour is that it is generally not possible to preserve the type information across program
    // mutations: a mutator may change the callsite of a function or modify the uses of a parameter, effectively invalidating the parameter types.
    // Parameter types are therefore only valid when a function is first created.
    public struct SubroutineDescriptor {
        // The parameter "structure", i.e. the number of parameters and whether there is a rest parameter, etc.
        // Currently, this information is also fully contained in the parameterTypes member. However, if we ever
        // add support for features such as parameter destructuring, this would no longer be the case.
        public let parameters: Parameters
        // Type information for every parameter. If no type information is specified, the parameters will all use .anything as type.
        public let parameterTypes: ParameterList

        public var count: Int {
            return parameters.count
        }

        public static func parameters(n: Int, hasRestParameter: Bool = false) -> SubroutineDescriptor {
            return SubroutineDescriptor(withParameters: Parameters(count: n, hasRestParameter: hasRestParameter))
        }

        public static func parameters(_ params: Parameter...) -> SubroutineDescriptor {
            return parameters(ParameterList(params))
        }

        public static func parameters(_ parameterTypes: ParameterList) -> SubroutineDescriptor {
            let parameters = Parameters(count: parameterTypes.count, hasRestParameter: parameterTypes.hasRestParameter)
            return SubroutineDescriptor(withParameters: parameters, ofTypes: parameterTypes)
        }

        private init(withParameters parameters: Parameters, ofTypes parameterTypes: ParameterList? = nil) {
            if let types = parameterTypes {
                assert(types.areValid())
                assert(types.count == parameters.count)
                assert(types.hasRestParameter == parameters.hasRestParameter)
                self.parameterTypes = types
            } else {
                self.parameterTypes = ParameterList(numParameters: parameters.count, hasRestParam: parameters.hasRestParameter)
                assert(self.parameterTypes.allSatisfy({ $0 == .plain(.anything) || $0 == .rest(.anything) }))
            }
            self.parameters = parameters
        }
    }

    @discardableResult
    public func buildPlainFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginPlainFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndPlainFunction())
        return instr.output
    }

    @discardableResult
    public func buildArrowFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginArrowFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildGeneratorFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginGeneratorFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginAsyncFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncArrowFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginAsyncArrowFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncArrowFunction())
        return instr.output
    }

    @discardableResult
    public func buildAsyncGeneratorFunction(with descriptor: SubroutineDescriptor, isStrict: Bool = false, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginAsyncGeneratorFunction(parameters: descriptor.parameters, isStrict: isStrict))
        body(Array(instr.innerOutputs))
        emit(EndAsyncGeneratorFunction())
        return instr.output
    }

    @discardableResult
    public func buildConstructor(with descriptor: SubroutineDescriptor, _ body: ([Variable]) -> ()) -> Variable {
        setParameterTypesForNextSubroutine(descriptor.parameterTypes)
        let instr = emit(BeginConstructor(parameters: descriptor.parameters))
        body(Array(instr.innerOutputs))
        emit(EndConstructor())
        return instr.output
    }

    public func doReturn(_ value: Variable? = nil) {
        if let returnValue = value {
            emit(Return(hasReturnValue: true), withInputs: [returnValue])
        } else {
            emit(Return(hasReturnValue: false))
        }
    }

    @discardableResult
    public func yield(_ value: Variable? = nil) -> Variable {
        if let argument = value {
            return emit(Yield(hasArgument: true), withInputs: [argument]).output
        } else {
            return emit(Yield(hasArgument: false)).output
        }
    }

    public func yieldEach(_ value: Variable) {
        emit(YieldEach(), withInputs: [value])
    }

    @discardableResult
    public func await(_ value: Variable) -> Variable {
        return emit(Await(), withInputs: [value]).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable] = []) -> Variable {
        return emit(CallFunction(numArguments: arguments.count), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func callFunction(_ function: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        guard !spreads.isEmpty else { return callFunction(function, withArgs: arguments) }
        return emit(CallFunctionWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [function] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable] = []) -> Variable {
        return emit(Construct(numArguments: arguments.count), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func construct(_ constructor: Variable, withArgs arguments: [Variable], spreading spreads: [Bool]) -> Variable {
        guard !spreads.isEmpty else { return construct(constructor, withArgs: arguments) }
        return emit(ConstructWithSpread(numArguments: arguments.count, spreads: spreads), withInputs: [constructor] + arguments).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable] = [], guard isGuarded: Bool = false) -> Variable {
        return emit(CallMethod(methodName: name, numArguments: arguments.count, isGuarded: isGuarded), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func callMethod(_ name: String, on object: Variable, withArgs arguments: [Variable], spreading spreads: [Bool], guard isGuarded: Bool = false) -> Variable {
        guard !spreads.isEmpty else { return callMethod(name, on: object, withArgs: arguments) }
        return emit(CallMethodWithSpread(methodName: name, numArguments: arguments.count, spreads: spreads, isGuarded: isGuarded), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable] = [], guard isGuarded: Bool = false) -> Variable {
        return emit(CallComputedMethod(numArguments: arguments.count, isGuarded: isGuarded), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func callComputedMethod(_ name: Variable, on object: Variable, withArgs arguments: [Variable], spreading spreads: [Bool], guard isGuarded: Bool = false) -> Variable {
        guard !spreads.isEmpty else { return callComputedMethod(name, on: object, withArgs: arguments) }
        return emit(CallComputedMethodWithSpread(numArguments: arguments.count, spreads: spreads, isGuarded: isGuarded), withInputs: [object, name] + arguments).output
    }

    @discardableResult
    public func unary(_ op: UnaryOperator, _ input: Variable) -> Variable {
        return emit(UnaryOperation(op), withInputs: [input]).output
    }

    @discardableResult
    public func binary(_ lhs: Variable, _ rhs: Variable, with op: BinaryOperator) -> Variable {
        return emit(BinaryOperation(op), withInputs: [lhs, rhs]).output
    }

    @discardableResult
    public func ternary(_ condition: Variable, _ lhs: Variable, _ rhs: Variable) -> Variable {
        return emit(TernaryOperation(), withInputs: [condition, lhs, rhs]).output
    }

    public func reassign(_ output: Variable, to input: Variable, with op: BinaryOperator) {
        emit(Update(op), withInputs: [output, input])
    }

    @discardableResult
    public func dup(_ v: Variable) -> Variable {
        return emit(Dup(), withInputs: [v]).output
    }

    public func reassign(_ output: Variable, to input: Variable) {
        emit(Reassign(), withInputs: [output, input])
    }

    @discardableResult
    public func destruct(_ input: Variable, selecting indices: [Int64], lastIsRest: Bool = false) -> [Variable] {
        let outputs = emit(DestructArray(indices: indices, lastIsRest: lastIsRest), withInputs: [input]).outputs
        return Array(outputs)
    }

    public func destruct(_ input: Variable, selecting indices: [Int64], into outputs: [Variable], lastIsRest: Bool = false) {
        emit(DestructArrayAndReassign(indices: indices, lastIsRest: lastIsRest), withInputs: [input] + outputs)
    }

    @discardableResult
    public func destruct(_ input: Variable, selecting properties: [String], hasRestElement: Bool = false) -> [Variable] {
        let outputs = emit(DestructObject(properties: properties, hasRestElement: hasRestElement), withInputs: [input]).outputs
        return Array(outputs)
    }

    public func destruct(_ input: Variable, selecting properties: [String], into outputs: [Variable], hasRestElement: Bool = false) {
        emit(DestructObjectAndReassign(properties: properties, hasRestElement: hasRestElement), withInputs: [input] + outputs)
    }

    @discardableResult
    public func compare(_ lhs: Variable, with rhs: Variable, using comparator: Comparator) -> Variable {
        return emit(Compare(comparator), withInputs: [lhs, rhs]).output
    }

    @discardableResult
    public func loadNamedVariable(_ name: String) -> Variable {
        return emit(LoadNamedVariable(name)).output
    }

    public func storeNamedVariable(_ name: String, _ value: Variable) {
        emit(StoreNamedVariable(name), withInputs: [value])
    }

    public func defineNamedVariable(_ name: String, _ value: Variable) {
        emit(DefineNamedVariable(name), withInputs: [value])
    }

    public func eval(_ string: String, with arguments: [Variable] = [], hasOutput: Bool = false) {
        emit(Eval(string, numArguments: arguments.count, hasOutput: hasOutput), withInputs: arguments)
    }

    public func buildWith(_ scopeObject: Variable, body: () -> Void) {
        emit(BeginWith(), withInputs: [scopeObject])
        body()
        emit(EndWith())
    }

    public func nop(numOutputs: Int = 0) {
        emit(Nop(numOutputs: numOutputs), withInputs: [])
    }

    public func callSuperConstructor(withArgs arguments: [Variable]) {
        emit(CallSuperConstructor(numArguments: arguments.count), withInputs: arguments)
    }

    @discardableResult
    public func callSuperMethod(_ name: String, withArgs arguments: [Variable] = []) -> Variable {
        return emit(CallSuperMethod(methodName: name, numArguments: arguments.count), withInputs: arguments).output
    }

    @discardableResult
    public func getPrivateProperty(_ name: String, of object: Variable) -> Variable {
        return emit(GetPrivateProperty(propertyName: name), withInputs: [object]).output
    }

    public func setPrivateProperty(_ name: String, of object: Variable, to value: Variable) {
        emit(SetPrivateProperty(propertyName: name), withInputs: [object, value])
    }

    public func updatePrivateProperty(_ name: String, of object: Variable, with value: Variable, using op: BinaryOperator) {
        emit(UpdatePrivateProperty(propertyName: name, operator: op), withInputs: [object, value])
    }

    @discardableResult
    public func callPrivateMethod(_ name: String, on object: Variable, withArgs arguments: [Variable] = []) -> Variable {
        return emit(CallPrivateMethod(methodName: name, numArguments: arguments.count), withInputs: [object] + arguments).output
    }

    @discardableResult
    public func getSuperProperty(_ name: String) -> Variable {
        return emit(GetSuperProperty(propertyName: name)).output
    }

    public func setSuperProperty(_ name: String, to value: Variable) {
        emit(SetSuperProperty(propertyName: name), withInputs: [value])
    }

    public func updateSuperProperty(_ name: String, with value: Variable, using op: BinaryOperator) {
        emit(UpdateSuperProperty(propertyName: name, operator: op), withInputs: [value])
    }

    public func buildIf(_ condition: Variable, ifBody: () -> Void) {
        emit(BeginIf(inverted: false), withInputs: [condition])
        ifBody()
        emit(EndIf())
    }

    public func buildIfElse(_ condition: Variable, ifBody: () -> Void, elseBody: () -> Void) {
        emit(BeginIf(inverted: false), withInputs: [condition])
        ifBody()
        emit(BeginElse())
        elseBody()
        emit(EndIf())
    }

    public struct SwitchBuilder {
        public typealias SwitchCaseGenerator = () -> ()
        fileprivate var caseGenerators: [(value: Variable?, fallsthrough: Bool, body: SwitchCaseGenerator)] = []
        var hasDefault: Bool = false

        public mutating func addDefault(fallsThrough: Bool = false, body: @escaping SwitchCaseGenerator) {
            assert(!hasDefault, "Cannot add more than one default case")
            hasDefault = true
            caseGenerators.append((nil, fallsThrough, body))
        }

        public mutating func add(_ v: Variable, fallsThrough: Bool = false, body: @escaping SwitchCaseGenerator) {
            caseGenerators.append((v, fallsThrough, body))
        }
    }

    public func buildSwitch(on switchVar: Variable, body: (inout SwitchBuilder) -> ()) {
        emit(BeginSwitch(), withInputs: [switchVar])

        var builder = SwitchBuilder()
        body(&builder)

        for (val, fallsThrough, bodyGenerator) in builder.caseGenerators {
            let inputs = val == nil ? [] : [val!]
            if inputs.count == 0 {
                emit(BeginSwitchDefaultCase(), withInputs: inputs)
            } else {
                emit(BeginSwitchCase(), withInputs: inputs)
            }
            bodyGenerator()
            emit(EndSwitchCase(fallsThrough: fallsThrough))
        }
        emit(EndSwitch())
    }

    public func buildSwitchCase(forCase caseVar: Variable, fallsThrough: Bool, body: () -> ()) {
        emit(BeginSwitchCase(), withInputs: [caseVar])
        body()
        emit(EndSwitchCase(fallsThrough: fallsThrough))
    }

    public func switchBreak() {
        emit(SwitchBreak())
    }

    public func buildWhileLoop(_ header: () -> Variable, _ body: () -> Void) {
        emit(BeginWhileLoopHeader())
        let cond = header()
        emit(BeginWhileLoopBody(), withInputs: [cond])
        body()
        emit(EndWhileLoop())
    }

    public func buildDoWhileLoop(do body: () -> Void, while header: () -> Variable) {
        emit(BeginDoWhileLoopBody())
        body()
        emit(BeginDoWhileLoopHeader())
        let cond = header()
        emit(EndDoWhileLoop(), withInputs: [cond])
    }

    // Build a simple for loop that declares one loop variable.
    public func buildForLoop(i initializer: () -> Variable, _ cond: (Variable) -> Variable, _ afterthought: (Variable) -> (), _ body: (Variable) -> ()) {
        emit(BeginForLoopInitializer())
        let initialValue = initializer()
        var loopVar = emit(BeginForLoopCondition(numLoopVariables: 1), withInputs: [initialValue]).innerOutput
        let cond = cond(loopVar)
        loopVar = emit(BeginForLoopAfterthought(numLoopVariables: 1), withInputs: [cond]).innerOutput
        afterthought(loopVar)
        loopVar = emit(BeginForLoopBody(numLoopVariables: 1)).innerOutput
        body(loopVar)
        emit(EndForLoop())
    }

    // Build arbitrarily complex for loops without any loop variables.
    public func buildForLoop(_ initializer: (() -> ())? = nil, _ cond: (() -> Variable)? = nil, _ afterthought: (() -> ())? = nil, _ body: () -> ()) {
        emit(BeginForLoopInitializer())
        initializer?()
        emit(BeginForLoopCondition(numLoopVariables: 0))
        let cond = cond?() ?? loadBool(true)
        emit(BeginForLoopAfterthought(numLoopVariables: 0), withInputs: [cond])
        afterthought?()
        emit(BeginForLoopBody(numLoopVariables: 0))
        body()
        emit(EndForLoop())
    }

    // Build arbitrarily complex for loops with one or more loop variables.
    public func buildForLoop(_ initializer: () -> [Variable], _ cond: (([Variable]) -> Variable)? = nil, _ afterthought: (([Variable]) -> ())? = nil, _ body: ([Variable]) -> ()) {
        emit(BeginForLoopInitializer())
        let initialValues = initializer()
        var loopVars = emit(BeginForLoopCondition(numLoopVariables: initialValues.count), withInputs: initialValues).innerOutputs
        let cond = cond?(Array(loopVars)) ?? loadBool(true)
        loopVars = emit(BeginForLoopAfterthought(numLoopVariables: initialValues.count), withInputs: [cond]).innerOutputs
        afterthought?(Array(loopVars))
        loopVars = emit(BeginForLoopBody(numLoopVariables: initialValues.count)).innerOutputs
        body(Array(loopVars))
        emit(EndForLoop())
    }

    public func buildForInLoop(_ obj: Variable, _ body: (Variable) -> ()) {
        let i = emit(BeginForInLoop(), withInputs: [obj]).innerOutput
        body(i)
        emit(EndForInLoop())
    }

    public func buildForOfLoop(_ obj: Variable, _ body: (Variable) -> ()) {
        let i = emit(BeginForOfLoop(), withInputs: [obj]).innerOutput
        body(i)
        emit(EndForOfLoop())
    }

    public func buildForOfLoop(_ obj: Variable, selecting indices: [Int64], hasRestElement: Bool = false, _ body: ([Variable]) -> ()) {
        let instr = emit(BeginForOfLoopWithDestruct(indices: indices, hasRestElement: hasRestElement), withInputs: [obj])
        body(Array(instr.innerOutputs))
        emit(EndForOfLoop())
    }

    public func buildRepeatLoop(n numIterations: Int, _ body: (Variable) -> ()) {
        let i = emit(BeginRepeatLoop(iterations: numIterations)).innerOutput
        body(i)
        emit(EndRepeatLoop())
    }

    public func buildRepeatLoop(n numIterations: Int, _ body: () -> ()) {
        emit(BeginRepeatLoop(iterations: numIterations, exposesLoopCounter: false))
        body()
        emit(EndRepeatLoop())
    }

    public func loopBreak() {
        emit(LoopBreak())
    }

    public func loopContinue() {
        emit(LoopContinue(), withInputs: [])
    }

    public func buildTryCatchFinally(tryBody: () -> (), catchBody: ((Variable) -> ())? = nil, finallyBody: (() -> ())? = nil) {
        assert(catchBody != nil || finallyBody != nil, "Must have either a Catch or a Finally block (or both)")
        emit(BeginTry())
        tryBody()
        if let catchBody = catchBody {
            let exception = emit(BeginCatch()).innerOutput
            catchBody(exception)
        }
        if let finallyBody = finallyBody {
            emit(BeginFinally())
            finallyBody()
        }
        emit(EndTryCatchFinally())
    }

    public func throwException(_ value: Variable) {
        emit(ThrowException(), withInputs: [value])
    }

    public func buildCodeString(_ body: () -> ()) -> Variable {
        let instr = emit(BeginCodeString())
        body()
        emit(EndCodeString())
        return instr.output
    }

    public func blockStatement(_ body: () -> Void) {
        emit(BeginBlockStatement())
        body()
        emit(EndBlockStatement())
    }

    public func doPrint(_ value: Variable) {
        emit(Print(), withInputs: [value])
    }


    /// Returns the next free variable.
    func nextVariable() -> Variable {
        assert(numVariables < Code.maxNumberOfVariables, "Too many variables")
        numVariables += 1
        return Variable(number: numVariables - 1)
    }

    @discardableResult
    private func internalAppend(_ instr: Instruction) -> Instruction {
        // Basic integrity checking
        assert(!instr.inouts.contains(where: { $0.number >= numVariables }))
        assert(instr.op.requiredContext.isSubset(of: contextAnalyzer.context))

        // The returned instruction will also contain its index in the program. Use that so the analyzers have access to the index.
        let instr = code.append(instr)
        analyze(instr)

        return instr
    }

    /// Set the parameter types for the next function, method, or constructor, which must be the the start of a function or method definition.
    /// Parameter types (and signatures in general) are only valid for the duration of the program generation, as they cannot be preserved across mutations.
    /// As such, the parameter types are linked to their instruction through the index of the instruction in the program.
    private func setParameterTypesForNextSubroutine(_ parameterTypes: ParameterList) {
        jsTyper.setParameters(forSubroutineStartingAt: code.count, to: parameterTypes)
    }

    /// Analyze the given instruction. Should be called directly after appending the instruction to the code.
    ///
    /// This will do the following:
    /// * Update the scope analysis to process any scope changes, which is required for correctly tracking the visible variables
    /// * Update the context analysis to process any context changes
    /// * Update the set of seen values and the variables that contain them for variable reuse
    /// * Update object literal state when fields are added to an object literal
    /// * Update the set of open function definitions, used to avoid trivial recursion
    /// * Run type inference to determine output types and any other type changes
    private func analyze(_ instr: Instruction) {
        assert(code.lastInstruction.op === instr.op)

        // Update variable- and context analysis.
        variableAnalyzer.analyze(instr)
        contextAnalyzer.analyze(instr)

        // Update object literal and class definition state.
        switch instr.op.opcode {
        case .beginObjectLiteral:
            activeObjectLiterals.push(ObjectLiteral(in: self))
        case .objectLiteralAddProperty(let op):
            currentObjectLiteral.existingProperties.append(op.propertyName)
        case .objectLiteralAddElement(let op):
            currentObjectLiteral.existingElements.append(op.index)
        case .objectLiteralAddComputedProperty:
            currentObjectLiteral.existingComputedProperties.append(instr.input(0))
        case .objectLiteralCopyProperties:
            // Cannot generally determine what fields this installs.
            break
        case .objectLiteralSetPrototype:
            currentObjectLiteral.hasPrototype = true
        case .beginObjectLiteralMethod(let op):
            currentObjectLiteral.existingMethods.append(op.methodName)
        case .beginObjectLiteralComputedMethod:
            currentObjectLiteral.existingComputedMethods.append(instr.input(0))
        case .beginObjectLiteralGetter(let op):
            currentObjectLiteral.existingGetters.append(op.propertyName)
        case .beginObjectLiteralSetter(let op):
            currentObjectLiteral.existingSetters.append(op.propertyName)
        case .endObjectLiteralMethod,
             .endObjectLiteralComputedMethod,
             .endObjectLiteralGetter,
             .endObjectLiteralSetter:
            break
        case .endObjectLiteral:
            activeObjectLiterals.pop()

        case .beginClassDefinition(let op):
            activeClassDefinitions.push(ClassDefinition(in: self, isDerived: op.hasSuperclass))
        case .beginClassConstructor:
            activeClassDefinitions.top.hasConstructor = true
        case .classAddInstanceProperty(let op):
            activeClassDefinitions.top.existingInstanceProperties.append(op.propertyName)
        case .classAddInstanceElement(let op):
            activeClassDefinitions.top.existingInstanceElements.append(op.index)
        case .classAddInstanceComputedProperty:
            activeClassDefinitions.top.existingInstanceComputedProperties.append(instr.input(0))
        case .beginClassInstanceMethod(let op):
            activeClassDefinitions.top.existingInstanceMethods.append(op.methodName)
        case .beginClassInstanceGetter(let op):
            activeClassDefinitions.top.existingInstanceGetters.append(op.propertyName)
        case .beginClassInstanceSetter(let op):
            activeClassDefinitions.top.existingInstanceSetters.append(op.propertyName)
        case .classAddStaticProperty(let op):
            activeClassDefinitions.top.existingStaticProperties.append(op.propertyName)
        case .classAddStaticElement(let op):
            activeClassDefinitions.top.existingStaticElements.append(op.index)
        case .classAddStaticComputedProperty:
            activeClassDefinitions.top.existingStaticComputedProperties.append(instr.input(0))
        case .beginClassStaticMethod(let op):
            activeClassDefinitions.top.existingStaticMethods.append(op.methodName)
        case .beginClassStaticGetter(let op):
            activeClassDefinitions.top.existingStaticGetters.append(op.propertyName)
        case .beginClassStaticSetter(let op):
            activeClassDefinitions.top.existingStaticSetters.append(op.propertyName)
        case .classAddPrivateInstanceProperty(let op):
            activeClassDefinitions.top.existingPrivateProperties.append(op.propertyName)
        case .beginClassPrivateInstanceMethod(let op):
            activeClassDefinitions.top.existingPrivateMethods.append(op.methodName)
        case .classAddPrivateStaticProperty(let op):
            activeClassDefinitions.top.existingPrivateProperties.append(op.propertyName)
        case .beginClassPrivateStaticMethod(let op):
            activeClassDefinitions.top.existingPrivateMethods.append(op.methodName)
        case .endClassDefinition:
            activeClassDefinitions.pop()
        case .beginClassStaticInitializer:
            break
        default:
            assert(!instr.op.requiredContext.contains(.objectLiteral))
            assert(!instr.op.requiredContext.contains(.classDefinition))
            break
        }

        // Track open functions.
        if instr.op is BeginAnyFunction {
            openFunctions.append(instr.output)
        } else if instr.op is EndAnyFunction {
            openFunctions.removeLast()
        }

        // Update type information.
        jsTyper.analyze(instr)
    }
}
