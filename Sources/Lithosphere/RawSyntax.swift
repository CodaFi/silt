//===------------------ RawSyntax.swift - Raw Syntax nodes ----------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

/// Box a value type into a reference type
class Box<T> {
  let value: T

  init(_ value: T) {
    self.value = value
  }
}

/// The data that is specific to a tree or token node
enum RawSyntaxData {
  /// A tree node with a kind and an array of children
  case node(kind: SyntaxKind, layout: [RawSyntax?])
  /// A token with a token kind, leading trivia, and trailing trivia
  case token(kind: TokenKind, leadingTrivia: Trivia, trailingTrivia: Trivia)
}

/// Represents the raw tree structure underlying the syntax tree. These nodes
/// have no notion of identity and only provide structure to the tree. They
/// are immutable and can be freely shared between syntax nodes.
final class RawSyntax {
  let data: RawSyntaxData
  let totalLength: SourceLength
  let presence: SourcePresence

  init(kind: SyntaxKind, layout: [RawSyntax?], length: SourceLength,
       presence: SourcePresence) {
    self.data = .node(kind: kind, layout: layout)
    self.totalLength = length
    self.presence = presence
  }

  init(kind: TokenKind, leadingTrivia: Trivia, trailingTrivia: Trivia,
       length: SourceLength, presence: SourcePresence) {
    self.data = .token(kind: kind, leadingTrivia: leadingTrivia,
                       trailingTrivia: trailingTrivia)
    self.totalLength = length
    self.presence = presence
  }

  /// The syntax kind of this raw syntax.
  var kind: SyntaxKind {
    fatalError()
//    switch data {
//    case .node(let kind, _): return kind
//    case .token(_, _, _): return .token
//    }
  }

  var tokenKind: TokenKind? {
    switch data {
    case .node(_, _): return nil
    case .token(let kind, _, _): return kind
    }
  }

  /// The layout of the children of this Raw syntax node.
  var layout: [RawSyntax?] {
    switch data {
    case .node(_, let layout): return layout
    case .token(_, _, _): return []
    }
  }

  /// Whether or not this node is a token one.
  var isToken: Bool {
    return tokenKind != nil
  }

  /// Whether this node is present in the original source.
  var isPresent: Bool {
    return presence == .present
  }

  /// Whether this node is missing from the original source.
  var isMissing: Bool {
    return presence == .missing
  }

  /// Creates a RawSyntax node that's marked missing in the source with the
  /// provided kind and layout.
  /// - Parameters:
  ///   - kind: The syntax kind underlying this node.
  ///   - layout: The children of this node.
  /// - Returns: A new RawSyntax `.node` with the provided kind and layout, with
  ///            `.missing` source presence.
  static func missing(_ kind: SyntaxKind) -> RawSyntax {
    return RawSyntax(kind: kind, layout: [], length: SourceLength.zero,
      presence: .missing)
  }

  /// Creates a RawSyntax token that's marked missing in the source with the
  /// provided kind and no leading/trailing trivia.
  /// - Parameter kind: The token kind.
  /// - Returns: A new RawSyntax `.token` with the provided kind, no
  ///            leading/trailing trivia, and `.missing` source presence.
  static func missingToken(_ kind: TokenKind) -> RawSyntax {
    return RawSyntax(kind: kind, leadingTrivia: [], trailingTrivia: [],
      length: SourceLength.zero, presence: .missing)
  }

  /// Returns a new RawSyntax node with the provided layout instead of the
  /// existing layout.
  /// - Note: This function does nothing with `.token` nodes --- the same token
  ///         is returned.
  /// - Parameter newLayout: The children of the new node you're creating.
  func replacingLayout(_ newLayout: [RawSyntax?]) -> RawSyntax {
    switch data {
    case let .node(kind, _):
      return .createAndCalcLength(kind: kind, layout: newLayout,
        presence: presence)
    case .token(_, _, _): return self
    }
  }

  /// Creates a new RawSyntax with the provided child appended to its layout.
  /// - Parameter child: The child to append
  /// - Note: This function does nothing with `.token` nodes --- the same token
  ///         is returned.
  /// - Return: A new RawSyntax node with the provided child at the end.
  func appending(_ child: RawSyntax) -> RawSyntax {
    var newLayout = layout
    newLayout.append(child)
    return replacingLayout(newLayout)
  }

  /// Returns the child at the provided cursor in the layout.
  /// - Parameter index: The index of the child you're accessing.
  /// - Returns: The child at the provided index.
  subscript<CursorType: RawRepresentable>(_ index: CursorType) -> RawSyntax?
    where CursorType.RawValue == Int {
      return layout[index.rawValue]
  }

  /// Replaces the child at the provided index in this node with the provided
  /// child.
  /// - Parameters:
  ///   - index: The index of the child to replace.
  ///   - newChild: The new child that should occupy that index in the node.
  func replacingChild(_ index: Int,
                      with newChild: RawSyntax?) -> RawSyntax {
    precondition(index < layout.count, "Cursor \(index) reached past layout")
    var newLayout = layout
    newLayout[index] = newChild
    return replacingLayout(newLayout)
  }
}

extension RawSyntax: TextOutputStreamable {
  /// Prints the RawSyntax node, and all of its children, to the provided
  /// stream. This implementation must be source-accurate.
  /// - Parameter stream: The stream on which to output this node.
  func write<Target>(to target: inout Target)
    where Target: TextOutputStream {
//    switch data {
//    case .node(_, let layout):
//      for child in layout {
//        guard let child = child else { continue }
//        child.write(to: &target)
//      }
//    case let .token(kind, leadingTrivia, trailingTrivia):
//      guard isPresent else { return }
//      for piece in leadingTrivia {
//        piece.write(to: &target)
//      }
//      target.write(kind.text)
//      for piece in trailingTrivia {
//        piece.write(to: &target)
//      }
//    }
      fatalError()
  }
}

extension RawSyntax {
  var leadingTrivia: Trivia? {
    switch data {
    case .node(_, let layout):
      for child in layout {
        guard let child = child else { continue }
        guard let result = child.leadingTrivia else { break }
        return result
      }
      return nil
    case let .token(_, leadingTrivia, _):
      return leadingTrivia
    }
  }

  var trailingTrivia: Trivia? {
    switch data {
    case .node(_, let layout):
      for child in layout.reversed() {
        guard let child = child else { continue }
        guard let result = child.trailingTrivia else { break }
        return result
      }
      return nil
    case let .token(_, _, trailingTrivia):
      return trailingTrivia
    }
  }
}

extension RawSyntax {
  var leadingTriviaLength: SourceLength {
    return leadingTrivia?.sourceLength ?? .zero
  }

  var trailingTriviaLength: SourceLength {
    return trailingTrivia?.sourceLength ?? .zero
  }

  /// The length of this node excluding its leading and trailing trivia.
  var contentLength: SourceLength {
    return totalLength - (leadingTriviaLength + trailingTriviaLength)
  }

  /// Convenience function to create a RawSyntax when its byte length is not
  /// known in advance, e.g. it is programmatically constructed instead of
  /// created by the parser.
  ///
  /// This is a separate function than in the initializer to make it more
  /// explicit and visible in the code for the instances where we don't have
  /// the length of the raw node already available.
  static func createAndCalcLength(kind: SyntaxKind, layout: [RawSyntax?],
      presence: SourcePresence) -> RawSyntax {
    let length: SourceLength
    if case .missing = presence {
      length = SourceLength.zero
    } else {
      var totalen = SourceLength.zero
      for child in layout {
        totalen += child?.totalLength ?? .zero
      }
      length = totalen
    }
    return .init(kind: kind, layout: layout, length: length, presence: presence)
  }

  /// Convenience function to create a RawSyntax when its byte length is not
  /// known in advance, e.g. it is programmatically constructed instead of
  /// created by the parser.
  ///
  /// This is a separate function than in the initializer to make it more
  /// explicit and visible in the code for the instances where we don't have
  /// the length of the raw node already available.
  static func createAndCalcLength(kind: TokenKind, leadingTrivia: Trivia,
      trailingTrivia: Trivia, presence: SourcePresence) -> RawSyntax {
    let length: SourceLength
    if case .missing = presence {
      length = SourceLength.zero
    } else {
      fatalError()
      // length = kind.sourceLength + leadingTrivia.sourceLength +
        // trailingTrivia.sourceLength
    }
    return .init(kind: kind, leadingTrivia: leadingTrivia,
      trailingTrivia: trailingTrivia, length: length, presence: presence)
  }
}

// This is needed purely to have a self assignment initializer for
// RawSyntax.init(from:Decoder) so we can reuse omitted nodes, instead of
// copying them.
private protocol _RawSyntaxFactory {}
extension _RawSyntaxFactory {
  init(_instance: Self) {
    self = _instance
  }
}
