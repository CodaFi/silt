import LLVM
import Seismography
import OuterCore
import PrettyStackTrace

final class IRGenFunction: PrimOpVisitor {
  unowned let IGM: IRGenModule
  var igr: IRGenRuntime!
  let scope: Scope
  let schedule: Schedule
  var function: Function?
  var blockMap = [Continuation: BasicBlock]()
  var primOpMap = [PrimOp: IRValue]()

  lazy var trapBlock: BasicBlock = {
    let insertBlock = B.insertBlock!
    let block = function!.appendBasicBlock(named: "trap")
    B.positionAtEnd(of: block)
    B.buildUnreachable()
    B.positionAtEnd(of: insertBlock)
    return block
  }()

  var B: IRBuilder {
    return IGM.B
  }

  init(irGenModule: IRGenModule, scope: Scope) {
    self.IGM = irGenModule
    self.schedule = Schedule(scope, .early)
    self.scope = scope
    self.igr = IRGenRuntime(irGenFunction: self)
  }

  func emitDeclaration() {
    trace("emitting LLVM IR declaration for function '\(scope.entry.name)'") {
      let name = IGM.mangler.mangle(scope.entry)
      let returnIGT = IRGenType(type: returnType(), irGenModule: IGM)
      let type = FunctionType(argTypes:
        scope.entry.parameters
             .dropLast().map {
               IRGenType(type: $0.type, irGenModule: IGM).emit()
             }, returnType: returnIGT.emit())
      self.function = B.addFunction(name, type: type)
    }
  }

  func emitBody() {
    trace("emitting LLVM IR declaration for function '\(scope.entry.name)'") {
      for block in schedule.blocks {
        let name = IGM.mangler.mangle(block.parent)
        let basicBlock = function!.appendBasicBlock(named: name)
        blockMap[block.parent] = basicBlock
      }
      for block in schedule.blocks {
        let bb = blockMap[block.parent]!
        B.positionAtEnd(of: bb)
        for primop in block.primops {
          _ = emit(primop)
        }
      }
    }
  }

  func emit(_ continuation: Continuation) {

  }

  func emit(_ primOp: PrimOp) -> IRValue {
    if let v = primOpMap[primOp] { return v }
    let value = visitPrimOp(primOp)
    primOpMap[primOp] = value
    return value
  }

  func emit(_ value: Value) -> IRValue {
    switch value {
    case let param as Seismography.Parameter:
      return function!.parameter(at: param.index)!
    case let op as PrimOp:
      return emit(op)
    default:
      return B.buildUnreachable()
    }
  }

  func returnType() -> GIRType {
    guard let lastParam = scope.entry.parameters.last else {
      fatalError("entry continuation with no parameters?")
    }
    guard let retCont = lastParam.type as? Seismography.FunctionType else {
      fatalError("last parameter is not continuation?")
    }
    guard let retType = retCont.arguments.first else {
      fatalError("return continuation has no parameters?")
    }
    return retType
  }

  func visitApplyOp(_ op: ApplyOp) -> IRValue {
    return trace("emitting LLVM IR for apply '\(op)'") {
      switch op.callee {
      case let param as Seismography.Parameter:
        // If we're getting a parameter as the callee of an `apply`, this is
        // a return continuation we're calling. If that's the case,
        guard param == param.parent.parameters.last else {
          fatalError("call parameter directly without function_ref?")
        }
        assert(op.arguments.count == 1,
               "return continuations must have 1 argument")
        return B.buildRet(emit(op.arguments.first!.value))
      case let funcRef as FunctionRefOp:
        let bb = emit(funcRef) as! BasicBlock
        return B.buildBr(bb)
      default:
        return B.buildUnreachable()
      }
    }
  }

  func visitCopyValueOp(_ op: CopyValueOp) -> IRValue {
    return trace("emitting LLVM IR for copy_value '\(op)'") {
      let val = emit(op.value.value)
      return igr.emitCopyValue(val)
    }
  }

  func visitDestroyValueOp(_ op: DestroyValueOp) -> IRValue {
    return trace("emitting LLVM IR for destroy_value '\(op)'") {
      let val = emit(op.value.value)
      igr.emitDestroyValue(val)
      return 0
    }
  }

  func visitFunctionRefOp(_ op: FunctionRefOp) -> IRValue {
    return trace("emitting LLVM IR for function_ref '\(op)'") {
      if let b = blockMap[op.function] { return b }
      // recursion is not handled yet
      return B.buildUnreachable()
    }
  }

  func visitSwitchConstrOp(_ op: SwitchConstrOp) -> IRValue {
    return trace("emitting LLVM IR for switch_constr '\(op)'") {
      guard let dataTy = op.matchedValue.type as? DataType else {
        fatalError("can only switch on simple types")
      }
      let igt = IRGenType(type: dataTy, irGenModule: IGM)
      let ty = igt.lower()
      switch ty {
      case .complexData(_, _, _):
        fatalError("complex data types are unsupported")
      case .simpleData(_):
        let indexesAndFuncs = op.patterns.map { caseDef -> (Int, BasicBlock) in
          // FIXME: String matching on constructor names is very bad here.
          let idx = dataTy.constructors.index { $0.name == caseDef.pattern }!
          return (idx, emit(caseDef.apply) as! BasicBlock)
        }
        let matched = emit(op.matchedValue)

        let defaultBlock = op.default.map(emit) as? BasicBlock ?? trapBlock

        let select = B.buildSwitch(matched, else: defaultBlock,
                                   caseCount: indexesAndFuncs.count)
        for (idx, bb) in indexesAndFuncs {
          let val = igt.initialize(tag: idx)
          select.addCase(val, bb)
        }
        return select
      case .void:
        break
      }
      return B.buildUnreachable()
    }
  }

  func visitDataInitOp(_ op: DataInitOp) -> IRValue {
    return trace("emitting LLVM IR for data_init '\(op)'") {
      guard op.operands.isEmpty else {
        // Cannot handle complex data types...
        return B.buildUnreachable()
      }
      guard let ty = op.dataType as? DataType else {
        fatalError("non data type in data_init?")
      }

      // FIXME: Adjust representation to actually store constructor tags instead
      //        of this fragile string lookup.
      let idx = ty.constructors.index { $0.name == op.constructor }!
      let igt = IRGenType(type: ty, irGenModule: IGM)
      return igt.initialize(tag: idx)
    }
  }

  func visitUnreachableOp(_ op: UnreachableOp) -> IRValue {
    return trace("emitting LLVM IR for unreachable '\(op)'") {
      return B.buildUnreachable()
    }
  }
}