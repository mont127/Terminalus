import Foundation

public enum TokenKind: String, Sendable {
    case keyword, type, string, number, comment, function, attribute, constant, variable, property, tag, heading, emphasis
}

public struct SyntaxToken: Equatable, Sendable {
    public var range: NSRange
    public var kind: TokenKind
}

public enum Language: String, CaseIterable, Sendable {
    case plain, swift, python, javascript, typescript, json, c, cpp, objc, go, rust, java, kotlin, ruby, shell,
         yaml, toml, markdown, html, xml, css, sql, lua, php, makefile, dockerfile

    public var displayName: String {
        switch self {
        case .plain: "Plain Text"
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .json: "JSON"
        case .c: "C"
        case .cpp: "C++"
        case .objc: "Objective-C"
        case .go: "Go"
        case .rust: "Rust"
        case .java: "Java"
        case .kotlin: "Kotlin"
        case .ruby: "Ruby"
        case .shell: "Shell"
        case .yaml: "YAML"
        case .toml: "TOML"
        case .markdown: "Markdown"
        case .html: "HTML"
        case .xml: "XML"
        case .css: "CSS"
        case .sql: "SQL"
        case .lua: "Lua"
        case .php: "PHP"
        case .makefile: "Makefile"
        case .dockerfile: "Dockerfile"
        }
    }

    public static func detect(fileName: String, firstLine: String = "") -> Language {
        let name = fileName.lowercased()
        switch name {
        case "makefile", "gnumakefile": return .makefile
        case "dockerfile", "containerfile": return .dockerfile
        case ".zshrc", ".zprofile", ".zshenv", ".zlogin", ".bashrc", ".bash_profile", ".profile", ".envrc": return .shell
        case "gemfile", "rakefile", "podfile", "fastfile": return .ruby
        case "package.resolved", ".prettierrc", ".eslintrc": return .json
        default: break
        }
        let ext = (name as NSString).pathExtension
        switch ext {
        case "swift": return .swift
        case "py", "pyw", "pyi": return .python
        case "js", "mjs", "cjs", "jsx": return .javascript
        case "ts", "tsx", "mts", "cts": return .typescript
        case "json", "jsonc", "geojson", "webmanifest": return .json
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "ino": return .cpp
        case "m", "mm": return .objc
        case "go": return .go
        case "rs": return .rust
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "rb", "gemspec": return .ruby
        case "sh", "bash", "zsh", "fish", "ksh", "command": return .shell
        case "yml", "yaml": return .yaml
        case "toml", "ini", "cfg", "conf", "properties", "editorconfig": return .toml
        case "md", "markdown", "mdx": return .markdown
        case "html", "htm", "xhtml", "vue", "svelte": return .html
        case "xml", "plist", "svg", "xib", "storyboard", "csproj", "entitlements": return .xml
        case "css", "scss", "sass", "less": return .css
        case "sql": return .sql
        case "lua": return .lua
        case "php": return .php
        case "mk": return .makefile
        default: break
        }
        if firstLine.hasPrefix("#!") {
            if firstLine.contains("python") { return .python }
            if firstLine.contains("node") { return .javascript }
            if firstLine.contains("ruby") { return .ruby }
            if firstLine.contains("sh") { return .shell }
        }
        return .plain
    }

    /// Prefix used by "Toggle Comment".
    public var lineComment: String? {
        switch self {
        case .swift, .javascript, .typescript, .c, .cpp, .objc, .go, .rust, .java, .kotlin, .php: "//"
        case .python, .ruby, .shell, .yaml, .toml, .makefile, .dockerfile: "#"
        case .sql, .lua: "--"
        case .plain, .json, .markdown, .html, .xml, .css: nil
        }
    }
}

/// Regex-based highlighter. Rules are applied in order, later ones overriding earlier ones; strings and
/// comments are matched together in one left-to-right pass at the end so `//` inside a string (or a quote
/// inside a comment) is handled correctly.
public enum SyntaxHighlighter {
    struct Rule {
        let regex: NSRegularExpression
        let kind: TokenKind
        let group: Int
    }

    struct Grammar {
        var rules: [Rule] = []
        /// Combined strings/comments regex: group 1 = comment, group 2 = string.
        var stringsAndComments: NSRegularExpression?
    }

    nonisolated(unsafe) private static var cache: [Language: Grammar] = [:]
    private static let lock = NSLock()

    public static func tokens(in text: String, language: Language, range: NSRange? = nil) -> [SyntaxToken] {
        let ns = text as NSString
        let r = range ?? NSRange(location: 0, length: ns.length)
        guard language != .plain, r.length > 0 else { return [] }
        let g = grammar(for: language)
        var out: [SyntaxToken] = []
        for rule in g.rules {
            rule.regex.enumerateMatches(in: text, options: [], range: r) { m, _, _ in
                guard let m else { return }
                let gr = m.range(at: rule.group)
                if gr.location != NSNotFound && gr.length > 0 { out.append(SyntaxToken(range: gr, kind: rule.kind)) }
            }
        }
        if let sc = g.stringsAndComments {
            sc.enumerateMatches(in: text, options: [], range: r) { m, _, _ in
                guard let m else { return }
                if m.range(at: 1).location != NSNotFound {
                    out.append(SyntaxToken(range: m.range(at: 1), kind: .comment))
                } else if m.numberOfRanges > 2, m.range(at: 2).location != NSNotFound {
                    out.append(SyntaxToken(range: m.range(at: 2), kind: .string))
                }
            }
        }
        return out
    }

    private static func grammar(for lang: Language) -> Grammar {
        lock.lock()
        defer { lock.unlock() }
        if let g = cache[lang] { return g }
        let g = build(lang)
        cache[lang] = g
        return g
    }

    private static func re(_ p: String, _ opts: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Patterns are constants; a failure is a programming error caught by the unit tests.
        (try? NSRegularExpression(pattern: p, options: opts)) ?? NSRegularExpression()
    }

    private static func words(_ list: String, caseInsensitive: Bool = false) -> NSRegularExpression {
        let alts = list.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "|")
        return re("\\b(?:\(alts))\\b", caseInsensitive ? [.caseInsensitive] : [])
    }

    private static func rule(_ r: NSRegularExpression, _ k: TokenKind, _ group: Int = 0) -> Rule { Rule(regex: r, kind: k, group: group) }

    private static let number = "\\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\\d[\\d_]*(?:\\.\\d[\\d_]*)?(?:[eE][+-]?\\d+)?)\\b"
    private static let call = "\\b([A-Za-z_][A-Za-z0-9_]*)(?=\\s*\\()"
    private static let capitalized = "\\b[A-Z][A-Za-z0-9_]*\\b"
    private static let dq = "\"(?:\\\\.|[^\"\\\\\\n])*\""
    private static let sq = "'(?:\\\\.|[^'\\\\\\n])*'"
    private static let bt = "`(?:\\\\.|[^`\\\\])*`"

    /// Builds the combined strings/comments regex from comment and string alternatives.
    private static func sc(comments: [String], strings: [String]) -> NSRegularExpression {
        let c = comments.isEmpty ? "(?!x)x" : comments.joined(separator: "|")
        let s = strings.isEmpty ? "(?!x)x" : strings.joined(separator: "|")
        return re("(\(c))|(\(s))", [.anchorsMatchLines])
    }

    private static let cBlock = "/\\*[\\s\\S]*?(?:\\*/|$(?![\\s\\S]))"
    private static let slashLine = "//[^\\n]*"
    private static let hashLine = "#[^\\n]*"

    private static func build(_ lang: Language) -> Grammar {
        var g = Grammar()
        switch lang {
        case .plain:
            break
        case .swift:
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type),
                rule(words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as async await is throws try some any actor nonisolated isolated mutating nonmutating override final lazy weak unowned convenience required dynamic indirect optional get set willSet didSet consume borrowing consuming macro"), .keyword),
                rule(words("true false nil self Self super"), .constant),
                rule(re(number), .number), rule(re("@[A-Za-z_][A-Za-z0-9_]*"), .attribute), rule(re("#(?:if|elseif|else|endif|available|selector|keyPath|file|line|function|warning|error|Preview)\\b"), .attribute),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: ["\"\"\"[\\s\\S]*?\"\"\"", dq])
        case .python:
            g.rules = [
                rule(re(call), .function, 1), rule(re("\\b(?:def|class)\\s+([A-Za-z_]\\w*)"), .function, 1),
                rule(words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case"), .keyword),
                rule(words("True False None self cls"), .constant), rule(words("int str float bool list dict set tuple bytes object type Exception"), .type),
                rule(re(number), .number), rule(re("^\\s*@[\\w.]+", [.anchorsMatchLines]), .attribute),
            ]
            g.stringsAndComments = sc(comments: [hashLine], strings: ["[rbfu]{0,2}\"\"\"[\\s\\S]*?\"\"\"", "[rbfu]{0,2}'''[\\s\\S]*?'''", "[rbfu]{0,2}" + dq, "[rbfu]{0,2}" + sq])
        case .javascript, .typescript:
            var kw = "async await break case catch class const continue debugger default delete do else export extends finally for from function if import in instanceof let new of return static super switch this throw try typeof var void while with yield get set"
            if lang == .typescript { kw += " interface type enum implements namespace declare abstract readonly private protected public keyof infer as is satisfies" }
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type), rule(words(kw), .keyword),
                rule(words("true false null undefined NaN Infinity"), .constant), rule(re(number), .number), rule(re("@[A-Za-z_]\\w*"), .attribute),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: [dq, sq, bt])
        case .json:
            g.rules = [rule(words("true false null"), .constant), rule(re("-?" + number), .number)]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: [dq])
            g.rules.append(rule(re("(\"(?:\\\\.|[^\"\\\\])*\")\\s*:"), .property, 1))
        case .c, .cpp, .objc:
            var kw = "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool _Bool"
            if lang == .cpp { kw += " class namespace template typename public private protected virtual override final new delete this throw try catch using constexpr nullptr noexcept operator friend explicit mutable static_cast dynamic_cast reinterpret_cast const_cast auto decltype" }
            if lang == .objc { kw += " @interface @implementation @end @property @protocol @selector @class self super nil YES NO id instancetype" }
            g.rules = [
                rule(re(call), .function, 1), rule(re("\\b[A-Z][A-Za-z0-9_]*\\b|\\b\\w+_t\\b"), .type), rule(words(kw), .keyword),
                rule(words("true false NULL nullptr"), .constant), rule(re(number + "[uUlLfF]*"), .number),
                rule(re("^\\s*#\\s*\\w+", [.anchorsMatchLines]), .attribute), rule(re("@\\w+"), .keyword),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: ["@?" + dq, sq, "(?<=#include )<[^>\\n]+>"])
        case .go:
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type),
                rule(words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"), .keyword),
                rule(words("true false nil iota"), .constant), rule(words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 string bool byte rune error any"), .type),
                rule(re(number), .number),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: [dq, "`[^`]*`", sq])
        case .rust:
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type), rule(re("\\b[a-z_]\\w*!"), .function),
                rule(words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type unsafe use where while"), .keyword),
                rule(words("true false self Self None Some Ok Err"), .constant), rule(words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String"), .type),
                rule(re(number), .number), rule(re("#!?\\[[^\\]]*\\]"), .attribute), rule(re("'[a-z_]\\w*\\b(?!')"), .attribute),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: ["r#*\"[\\s\\S]*?\"#*", dq])
        case .java, .kotlin:
            var kw = "abstract assert break case catch class continue default do else enum extends final finally for if implements import instanceof interface native new package private protected public return static super switch synchronized this throw throws try void volatile while var"
            if lang == .kotlin { kw += " fun val when object companion data sealed open override internal lateinit by in is as typealias suspend inline reified init" }
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type), rule(words(kw), .keyword),
                rule(words("true false null"), .constant), rule(words("int long short byte char boolean float double"), .type),
                rule(re(number + "[lLfFdD]?"), .number), rule(re("@\\w+"), .attribute),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine], strings: ["\"\"\"[\\s\\S]*?\"\"\"", dq, sq])
        case .ruby:
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type),
                rule(words("alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return then undef unless until when while yield require require_relative attr_accessor attr_reader private protected public"), .keyword),
                rule(words("true false nil self"), .constant), rule(re(number), .number), rule(re(":[A-Za-z_]\\w*[?!]?"), .constant),
                rule(re("@{1,2}[A-Za-z_]\\w*"), .variable),
            ]
            g.stringsAndComments = sc(comments: ["^=begin[\\s\\S]*?^=end", hashLine], strings: [dq, sq])
        case .shell:
            g.rules = [
                rule(re("^\\s*(?:function\\s+)?([A-Za-z_][\\w-]*)\\s*\\(\\)", [.anchorsMatchLines]), .function, 1),
                rule(words("if then else elif fi for while until do done case esac in function return select time local export readonly declare typeset unset shift source alias break continue exit eval exec trap set"), .keyword),
                rule(re("\\$\\{[^}\\n]*\\}|\\$[A-Za-z_][A-Za-z0-9_]*|\\$[0-9@#?*$!-]"), .variable),
                rule(re("(?<=\\s)--?[A-Za-z][\\w-]*"), .attribute), rule(re(number), .number),
            ]
            g.stringsAndComments = sc(comments: ["(?<![\\w$\\\\{])#[^\\n]*"], strings: [dq, "'[^']*'"])
        case .yaml:
            g.rules = [
                rule(re("^\\s*(?:- )?([A-Za-z0-9_.\"'-]+)\\s*:(?=\\s|$)", [.anchorsMatchLines]), .property, 1),
                rule(words("true false null yes no on off True False"), .constant), rule(re(number), .number),
                rule(re("[&*][A-Za-z0-9_-]+"), .attribute), rule(re("^---|^\\.\\.\\.", [.anchorsMatchLines]), .keyword),
            ]
            g.stringsAndComments = sc(comments: ["(?<!\\S)#[^\\n]*"], strings: [dq, sq])
        case .toml:
            g.rules = [
                rule(re("^\\s*\\[\\[?[^\\]\\n]+\\]\\]?", [.anchorsMatchLines]), .type),
                rule(re("^\\s*([A-Za-z0-9_.-]+)\\s*=", [.anchorsMatchLines]), .property, 1),
                rule(words("true false"), .constant), rule(re(number), .number),
            ]
            g.stringsAndComments = sc(comments: ["(?<!\\S)[#;][^\\n]*"], strings: ["\"\"\"[\\s\\S]*?\"\"\"", dq, sq])
        case .markdown:
            g.rules = [
                rule(re("^#{1,6} .*$", [.anchorsMatchLines]), .heading),
                rule(re("\\*\\*[^*\\n]+\\*\\*|__[^_\\n]+__"), .emphasis), rule(re("(?<![*\\w])\\*[^*\\n]+\\*(?!\\*)"), .emphasis),
                rule(re("\\[[^\\]\\n]+\\]\\([^)\\n]+\\)"), .function), rule(re("^\\s*(?:[-*+]|\\d+\\.)\\s", [.anchorsMatchLines]), .keyword),
                rule(re("^>.*$", [.anchorsMatchLines]), .comment),
            ]
            g.stringsAndComments = sc(comments: ["<!--[\\s\\S]*?-->"], strings: ["^```[\\s\\S]*?^```", "`[^`\\n]+`"])
        case .html, .xml:
            g.rules = [
                rule(re("</?([A-Za-z][\\w:.-]*)"), .tag, 1), rule(re("\\s([A-Za-z_:][\\w:.-]*)(?=\\s*=)"), .attribute, 1),
                rule(re("&[A-Za-z0-9#]+;"), .constant), rule(re("<!DOCTYPE[^>]*>|<\\?xml[^>]*\\?>", [.caseInsensitive]), .keyword),
            ]
            g.stringsAndComments = sc(comments: ["<!--[\\s\\S]*?-->"], strings: [dq, sq])
        case .css:
            g.rules = [
                rule(re("([.#]?[A-Za-z_-][\\w-]*)(?=[^{}\\n]*\\{)"), .tag, 1), rule(re("([A-Za-z-]+)\\s*:(?!:)"), .property, 1),
                rule(re("#[0-9a-fA-F]{3,8}\\b"), .number), rule(re("-?\\d*\\.?\\d+(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?\\b"), .number),
                rule(re("@[\\w-]+"), .keyword), rule(re("!important"), .keyword), rule(re("var\\(--[\\w-]+\\)|--[\\w-]+"), .variable),
            ]
            g.stringsAndComments = sc(comments: [cBlock], strings: [dq, sq])
        case .sql:
            g.rules = [
                rule(words("select from where and or not insert into values update set delete create table drop alter add index view join left right inner outer full on as group by order having limit offset union all distinct case when then else end primary key foreign references default null is in like between exists returning with begin commit rollback transaction", caseInsensitive: true), .keyword),
                rule(words("int integer text varchar char boolean date timestamp float real numeric serial bigint json jsonb", caseInsensitive: true), .type),
                rule(words("true false null", caseInsensitive: true), .constant), rule(re(number), .number), rule(re(call), .function, 1),
            ]
            g.stringsAndComments = sc(comments: [cBlock, "--[^\\n]*"], strings: [sq, dq])
        case .lua:
            g.rules = [
                rule(re(call), .function, 1),
                rule(words("and break do else elseif end for function goto if in local not or repeat return then until while"), .keyword),
                rule(words("true false nil self"), .constant), rule(re(number), .number),
            ]
            g.stringsAndComments = sc(comments: ["--\\[\\[[\\s\\S]*?\\]\\]", "--[^\\n]*"], strings: ["\\[\\[[\\s\\S]*?\\]\\]", dq, sq])
        case .php:
            g.rules = [
                rule(re(call), .function, 1), rule(re(capitalized), .type),
                rule(words("abstract and array as break case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global goto if implements include instanceof interface isset list match namespace new or print private protected public readonly require return static switch throw trait try unset use var while yield"), .keyword),
                rule(words("true false null TRUE FALSE NULL"), .constant), rule(re("\\$[A-Za-z_]\\w*"), .variable), rule(re(number), .number),
                rule(re("<\\?php|\\?>"), .tag),
            ]
            g.stringsAndComments = sc(comments: [cBlock, slashLine, hashLine], strings: [dq, sq])
        case .makefile:
            g.rules = [
                rule(re("^([^\\s:#=][^:#=\\n]*?):(?!=)", [.anchorsMatchLines]), .function, 1),
                rule(re("\\$\\([^)\\n]+\\)|\\$\\{[^}\\n]+\\}|\\$[@<^?*%]"), .variable),
                rule(re("^\\s*([A-Za-z_][\\w.]*)\\s*[:+?]?=", [.anchorsMatchLines]), .property, 1),
                rule(words("ifeq ifneq ifdef ifndef else endif include define endef export override .PHONY"), .keyword),
            ]
            g.stringsAndComments = sc(comments: [hashLine], strings: [dq, sq])
        case .dockerfile:
            g.rules = [
                rule(re("^\\s*(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|AS)\\b", [.anchorsMatchLines, .caseInsensitive]), .keyword),
                rule(re("\\$\\{[^}\\n]+\\}|\\$[A-Za-z_]\\w*"), .variable),
            ]
            g.stringsAndComments = sc(comments: ["^\\s*#[^\\n]*"], strings: [dq, sq])
        }
        return g
    }
}

/// A symbol for the Outline panel.
public struct OutlineSymbol: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case function, type, property, section
    }

    public var name: String
    public var kind: Kind
    /// 1-based line number.
    public var line: Int
    /// Nesting level (from indentation or heading level).
    public var depth: Int
    public var id: String { "\(line):\(name)" }
}

public enum OutlineExtractor {
    private struct Pattern {
        let regex: NSRegularExpression
        let nameGroup: Int
        let kindGroup: Int?
        let fixedKind: OutlineSymbol.Kind
    }

    private static func p(_ s: String, name: Int, kindGroup: Int? = nil, _ kind: OutlineSymbol.Kind = .function) -> Pattern {
        Pattern(regex: (try? NSRegularExpression(pattern: s, options: [.anchorsMatchLines])) ?? NSRegularExpression(),
                nameGroup: name, kindGroup: kindGroup, fixedKind: kind)
    }

    private static func patterns(_ lang: Language) -> [Pattern] {
        switch lang {
        case .swift:
            return [p("^([ \\t]*)(?:@\\w+(?:\\([^)]*\\))?\\s+)*(?:(?:public|private|internal|fileprivate|open|static|final|override|mutating|nonisolated|class|indirect)\\s+)*(func|class|struct|enum|protocol|extension|actor|init|typealias)\\b\\s*([A-Za-z_][\\w.]*)?", name: 3, kindGroup: 2)]
        case .python:
            return [p("^([ \\t]*)(def|class|async def)\\s+([A-Za-z_]\\w*)", name: 3, kindGroup: 2)]
        case .javascript, .typescript:
            return [
                p("^([ \\t]*)(?:export\\s+)?(?:default\\s+)?(?:async\\s+)?(function|class|interface|type|enum)\\*?\\s+([A-Za-z_$][\\w$]*)", name: 3, kindGroup: 2),
                p("^([ \\t]*)(?:export\\s+)?(?:const|let|var)\\s+([A-Za-z_$][\\w$]*)\\s*=\\s*(?:async\\s*)?(?:\\([^)\\n]*\\)|[A-Za-z_$][\\w$]*)\\s*=>", name: 2),
                p("^([ \\t]+)(?:async\\s+|static\\s+|get\\s+|set\\s+)*([A-Za-z_$][\\w$]*)\\s*\\([^)\\n]*\\)\\s*\\{", name: 2),
            ]
        case .go:
            return [p("^()func\\s+(?:\\([^)]*\\)\\s*)?([A-Za-z_]\\w*)", name: 2), p("^()type\\s+([A-Za-z_]\\w*)", name: 2, .type)]
        case .rust:
            return [p("^([ \\t]*)(?:pub(?:\\([^)]*\\))?\\s+)?(?:async\\s+|unsafe\\s+|const\\s+)*(fn|struct|enum|trait|impl|mod|type)\\s+(?:<[^>]*>\\s*)?([A-Za-z_][\\w:<>]*)", name: 3, kindGroup: 2)]
        case .c, .cpp, .objc:
            return [
                p("^()(?!(?:if|for|while|switch|return|else)\\b)[A-Za-z_][\\w\\s\\*&:<>,]*?\\b([A-Za-z_~][\\w:~]*)\\s*\\([^;{}]*\\)\\s*(?:const\\s*)?\\{?\\s*$", name: 2),
                p("^()(?:typedef\\s+)?(?:struct|class|enum|union)\\s+([A-Za-z_]\\w*)", name: 2, .type),
                p("^()[-+]\\s*\\([^)]*\\)\\s*([A-Za-z_]\\w*)", name: 2),
                p("^()@(?:interface|implementation|protocol)\\s+([A-Za-z_]\\w*)", name: 2, .type),
            ]
        case .java, .kotlin:
            return [p("^([ \\t]*)(?:[\\w@]+\\s+)*(class|interface|enum|object|fun)\\s+([A-Za-z_]\\w*)", name: 3, kindGroup: 2)]
        case .ruby:
            return [p("^([ \\t]*)(def|class|module)\\s+([\\w.:?!]+)", name: 3, kindGroup: 2)]
        case .shell:
            return [p("^([ \\t]*)(?:function\\s+)?([A-Za-z_][\\w-]*)\\s*\\(\\)", name: 2)]
        case .lua:
            return [p("^([ \\t]*)(?:local\\s+)?function\\s+([\\w.:]+)", name: 2)]
        case .php:
            return [p("^([ \\t]*)(?:[a-z]+\\s+)*(function|class|interface|trait)\\s+([A-Za-z_]\\w*)", name: 3, kindGroup: 2)]
        case .css:
            return [p("^()([^{}\\n/@][^{}\\n]*?)\\s*\\{", name: 2, .type)]
        case .yaml:
            return [p("^()([A-Za-z_][\\w-]*):", name: 2, .property)]
        case .toml:
            return [p("^()\\[\\[?([^\\]\\n]+)\\]\\]?", name: 2, .section)]
        case .makefile:
            return [p("^()([^\\s:#=.][^:#=\\n]*?):(?!=)", name: 2)]
        case .markdown, .plain, .json, .html, .xml, .sql, .dockerfile:
            return []
        }
    }

    public static func symbols(in text: String, language: Language) -> [OutlineSymbol] {
        let ns = text as NSString
        var out: [OutlineSymbol] = []
        if language == .markdown {
            let re = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.+)$", options: [.anchorsMatchLines])
            var inFence = false
            var lineNo = 0
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { line, _, _, _ in
                lineNo += 1
                guard let line else { return }
                if line.hasPrefix("```") { inFence.toggle(); return }
                guard !inFence, let m = re?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return }
                let level = m.range(at: 1).length
                out.append(OutlineSymbol(name: (line as NSString).substring(with: m.range(at: 2)), kind: .section, line: lineNo, depth: level - 1))
            }
            return out
        }
        let pats = patterns(language)
        guard !pats.isEmpty else { return [] }
        // Line starts for offset → line conversion.
        var starts: [Int] = [0]
        for (i, u) in text.utf16.enumerated() where u == 10 { starts.append(i + 1) }
        func line(for offset: Int) -> Int {
            var lo = 0, hi = starts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
            }
            return lo + 1
        }
        var seen = Set<Int>()
        for pat in pats {
            pat.regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m else { return }
                let nr = m.range(at: pat.nameGroup)
                let ln = line(for: m.range.location + (m.range.length > 0 && ns.character(at: m.range.location) == 10 ? 1 : 0))
                guard !seen.contains(ln) else { return }
                var name = nr.location != NSNotFound ? ns.substring(with: nr).trimmingCharacters(in: .whitespaces) : ""
                var kind = pat.fixedKind
                if let kg = pat.kindGroup, m.range(at: kg).location != NSNotFound {
                    let k = ns.substring(with: m.range(at: kg))
                    switch k {
                    case "class", "struct", "enum", "protocol", "extension", "actor", "interface", "trait", "impl", "module", "type", "object", "typealias", "mod":
                        kind = .type
                    default:
                        kind = .function
                    }
                    if name.isEmpty { name = k }
                }
                guard !name.isEmpty else { return }
                let indent = m.numberOfRanges > 1 && m.range(at: 1).location != NSNotFound ? m.range(at: 1).length : 0
                seen.insert(ln)
                out.append(OutlineSymbol(name: name, kind: kind, line: ln, depth: min(6, indent / 2)))
            }
        }
        return out.sorted { $0.line < $1.line }
    }
}
