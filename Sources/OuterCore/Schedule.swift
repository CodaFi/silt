//
//  Schedule.swift
//  siltPackageDescription
//
//  Created by Robert Widmann on 2/20/18.
//

final class Schedule {
  enum Tag {
    case early
    case late
  }

  final class Block: Equatable, Hashable {
    var parent: Continuation
    var primops: [PrimOp]
    var index: Int

    init(_ parent: Continuation, _ primops: [PrimOp], _ idx: Int) {
      self.parent = parent
      self.primops = primops
      self.index = idx
    }

    public static func ==(lhs: Block, rhs: Block) -> Bool {
      return lhs === rhs
    }
    
    public var hashValue: Int {
      return "\(ObjectIdentifier(self).hashValue)".hashValue
    }
  }

  let scope: Scope
  let tag: Tag
  var blocks: [Block] = []
  var indices: [Continuation: Int] = [:]
  init(_ scope: Scope, _ tag: Tag) {
    self.scope = scope
    self.tag = tag

    // until we have sth better simply use the RPO of the CFG
    var i = 0
    for n in scope.cfg.reverse_post_order {
      defer { i += 1 }
      self.blocks.append(Block(n, [], i))
      self.indices[n] = i
    }
    _ = Scheduler(self)
  }

  func block(_ c : Continuation) -> Block {
    return self.blocks[self.indices[c]!]
  }

  func dump() {
    for block in self.blocks {
      block.parent.dump()
      for primop in block.primops {
        primop.dump()
      }
    }
  }
}

private final class Scheduler {
  let scope: Scope
  let schedule: Schedule
  private var def2uses = [Value: [Operand]]()

  private var def2early = [Value: Continuation]()
  private var def2late = [Value: Continuation]()

  init(_ schedule: Schedule) {
    self.scope = schedule.scope
    self.schedule = schedule
    self.compute_def2uses()
    switch schedule.tag {
    case .early:
      for (_, uses) in self.def2uses {
        for operand in uses.reversed() {
          guard let primop = operand.owningOp else {
            continue
          }
          let cont = self.schedule_early(primop)
          schedule.block(cont).primops.append(primop)
        }
      }
    case .late:
      fatalError()
//      for (primop, _) in def2uses where primop is PrimOp {
//        _ = self.schedule_late(primop)
//      }
    }
  }

  func schedule_early(_ def: Value) -> Continuation {
    if let early = self.def2early[def] {
      return early
    }

    if let param = def as? Parameter {
      self.def2early[def] = param.parent
      return param.parent
    }

    var result = self.scope.entry
    for op in (def as! PrimOp).operands {
      guard !(op.value is Continuation) && def2uses[op.value] != nil else {
        continue
      }

      let n = self.schedule_early(op.value)
//      guard self.scope.cfg.domtree.depth(n) > self.scope.cfg.domtree.depth(result) else {
//        continue
//      }
      result = n
    }

    self.def2early[def] = result
    return result
  }

  private func compute_def2uses() {
    var queue = [Value]()
    var done = Set<Value>()

    let enqueue = { (def : Value, users: AnySequence<Operand>) in
      for use in users {
        guard let owningOp = use.owningOp else {
          continue
        }

        guard !done.contains(owningOp) else {
          continue
        }

        guard self.scope.contains(owningOp) else {
          continue
        }

        self.def2uses[def, default: []].append(use)
        if done.insert(owningOp).inserted {
          queue.append(owningOp)
        }
      }
    }
    for n in self.scope.cfg.reverse_post_order {
      queue.append(n);
      let p = done.insert(n)
      assert(p.inserted)
    }

    while !queue.isEmpty {
      let def = queue.removeFirst()
      guard let cont = def as? Continuation else {
        continue
      }
      for param in cont.parameters {
        enqueue(param, param.users)
      }
    }
  }
}
