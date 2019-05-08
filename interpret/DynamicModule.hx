package interpret;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Printer;
#end

import interpret.Types;

using StringTools;

/** Like haxe modules, but resolved at runtime. */
class DynamicModule {

    static var _adding = false;

    static var _nextId = 1;

/// Properties

    public var id(default,null):Int = _nextId++;

    public var items(get,null):Map<String,RuntimeItem> = null;
    function get_items():Map<String,RuntimeItem> {
        if (!_adding && lazyLoad != null) {
            if (lazyLoad != null) {
                var cb = lazyLoad;
                lazyLoad = null;
                cb(this);
            }
        }
        return this.items;
    }

    public var dynamicClasses(default,null):Map<String,DynamicClass> = null;

    public var imports(default,null):ResolveImports = null;

    public var usings(default,null):ResolveUsings = null;

    public var pack:String = null;

    public var aliases(default,null):Map<String,String> = new Map();

    @:noCompletion
    public var lazyLoad:DynamicModule->Void = null;

    @:noCompletion
    public var onLink:Void->Void = null;

    /** Internal map of classes and the superclass they extend (if any) */
    @:noCompletion
    public var superClasses:Map<String,String> = new Map();

    /** Internal map of classes and the interfaces they implement (if any) */
    @:noCompletion
    public var interfaces:Map<String,Map<String,Bool>> = new Map();

    public var typePath:String = null;

/// Lifecycle

    public function new() {

    } //new

    public function add(name:String, rawItem:Dynamic, kind:Int, ?extra:Dynamic) {

        _adding = true;

        if (items == null) items = new Map();

        switch (kind) {
            case ModuleItemKind.CLASS:
                items.set(name, ClassItem(rawItem, id, name));
            case ModuleItemKind.CLASS_FIELD:
                var extendedType:String = extra;
                if (extendedType != null) {
                    items.set(name, ExtensionItem(ClassFieldItem(rawItem, id, name), extendedType));
                } else {
                    items.set(name, ClassFieldItem(rawItem, id, name));
                }
            case ModuleItemKind.ENUM:
                items.set(name, EnumItem(rawItem, id, name));
            case ModuleItemKind.ENUM_FIELD:
                var numArgs:Int = extra;
                items.set(name, EnumFieldItem(rawItem, name, numArgs));
            default:
        }

        _adding = false;

    } //add

    public function alias(alias:String, name:String) {

        aliases.set(alias, name);

    } //alias

    public function addSuperClass(child:String, superClass:String) {

        superClasses.set(child, superClass);

    } //addSuperClass

    public function addInterface(child:String, interface_:String) {

        var subItems = interfaces.get(child);
        if (subItems == null) {
            subItems = new Map();
            interfaces.set(child, subItems);
        }
        subItems.set(interface_, true);

    } //addInterface

/// From string

    static public function fromString(env:Env, moduleName:String, haxe:String, ?options:ModuleOptions) {

        var converter = new ConvertHaxe(haxe);

        var interpretableOnly = false;
        var allowUnresolvedImports = false;
        var extendingClassName = null;
        var extendedClassName = null;
        if (options != null) {
            interpretableOnly = options.interpretableOnly;
            allowUnresolvedImports = options.allowUnresolvedImports;
            extendingClassName = options.extendingClassName;
            extendedClassName = options.extendedClassName;
        }

        // Transform class token if needed
        if (extendingClassName != null && extendedClassName != null) {
            converter.transformToken = function(token) {
                switch (token) {
                    case TType(data):
                        if (data.kind == CLASS && data.name == extendedClassName) {
                            data.parent = {
                                name: extendedClassName,
                                kind: SUPERCLASS
                            };
                            data.name = extendingClassName;
                            data.interfaces = [{
                                name: 'Interpretable',
                                kind: INTERFACE
                            }];
                            return TType(data);
                        }
                    default:
                }
                return token;
            };
        }

        converter.convert();

        var module = new DynamicModule();
        module.dynamicClasses = new Map();

        module.imports = new ResolveImports(env);
        module.usings = new ResolveUsings(env);

        function consumeTokens(shallow:Bool) {

            var currentClassPath:String = null;
            var dynClass:DynamicClass = null;
            var modifiers = new Map<String,Bool>();
            var interpretableField = false;
            var packagePrefix:String = '';

            for (token in converter.tokens) {
                switch (token) {

                    case TPackage(data):
                        module.imports.pack = data.path;
                        module.pack = data.path;
                        packagePrefix = data.path != null && data.path != '' ? data.path + '.' : '';
                
                    case TImport(data):
                        if (shallow) continue;
                        module.imports.addImport(data, allowUnresolvedImports);
                    
                    case TUsing(data):
                        if (shallow) continue;
                        module.usings.addUsing(data, allowUnresolvedImports);

                    case TModifier(data):
                        modifiers.set(data.name, true);

                    case TType(data):
                        if (data.kind == CLASS) {
                            var classAllowed = false;
                            if (interpretableOnly) {
                                // If only keeping interpretable classes, skip any that doesn't
                                // implement interpret.Interpretable interface
                                if (data.interfaces != null) {
                                    for (item in data.interfaces) {
                                        var resolvedType = TypeUtils.toResolvedType(module.imports, item.name);
                                        if (resolvedType == 'Interpretable' || resolvedType == 'interpret.Interpretable') {
                                            classAllowed = true;
                                            break;
                                        }
                                    }
                                }
                            }
                            else {
                                classAllowed = true;
                            }
                            if (classAllowed) {
                                dynClass = shallow ? null : new DynamicClass(env, {
                                    tokens: converter.tokens,
                                    targetClass: data.name,
                                    moduleOptions: options
                                });
                                if (!shallow) module.dynamicClasses.set(data.name, dynClass);
                                currentClassPath = packagePrefix + (data.name == moduleName ? data.name : moduleName + '.' + data.name);
                                module.add(currentClassPath, null, ModuleItemKind.CLASS, null);
                                if (!shallow) {
                                    if (data.parent != null) {
                                        module.addSuperClass(currentClassPath, TypeUtils.toResolvedType(module.imports, data.parent.name));
                                    }
                                    if (data.interfaces != null) {
                                        for (item in data.interfaces) {
                                            module.addInterface(currentClassPath, TypeUtils.toResolvedType(module.imports, item.name));
                                        }
                                    }
                                }
                            }
                            else {
                                dynClass = null;
                                currentClassPath = null;
                            }
                        }
                        else {
                            currentClassPath = null;
                            dynClass = null;
                        }
                        // Reset modifiers
                        modifiers = new Map<String,Bool>();
                    
                    case TField(data):
                        // If only keeping interpretable fields, skip any that doesn't
                        // have @interpret meta
                        if (currentClassPath != null && (!interpretableOnly || interpretableField)) {
                            if (modifiers.exists('static')) {
                                // When filtering with interpretableOnly, skip vars as it only works
                                // on methods for now
                                if (data.kind == VAR && !interpretableOnly) {
                                    module.add(currentClassPath + '.' + data.name, null, ModuleItemKind.CLASS_FIELD, null);
                                }
                                else if (data.kind == METHOD) {
                                    var extendedType = null;
                                    if (data.args.length > 0) {
                                        var firstArg = data.args[0];
                                        if (firstArg.type != null) {
                                            extendedType = firstArg.type;
                                        }
                                    }
                                    if (extendedType != null) {
                                        extendedType = TypeUtils.toResolvedType(module.imports, extendedType);
                                    }
                                    module.add(currentClassPath + '.' + data.name, null, ModuleItemKind.CLASS_FIELD, extendedType);
                                }
                            }
                        }
                        // Reset @interpret meta
                        interpretableField = false;
                    
                    case TMeta(data):
                        if (data.name == 'interpret') {
                            interpretableField = true;
                        }

                    default:                
                }
            }
        }

        consumeTokens(true);
        module.onLink = function() {
            consumeTokens(false);
        };

        return module;

    } //fromString

/// From static module

    /** Return a `DynamicModule` instance from a haxe module as it was at compile time. 
        Allows to easily map a Haxe modules to their scriptable equivalent. */
    macro static public function fromStatic(e:Expr) {

        var pos = Context.currentPos();
        var typePath = new Printer().printExpr(e);
        var pack = [];
        var parts = typePath.split('.');
        while (parts.length > 1) {
            pack.push(parts.shift());
        }
        var packString = pack.join('.');
        var name = parts[0];
        var complexType = TPath({pack: pack, name: name});
        var type = null;
        try {
            Context.resolveType(complexType, pos);
        } catch (e:Dynamic) {
            // Module X does not define type X, which is fine
        }

        var module = Context.getModule(typePath);

        var abstractTypes:Array<String> = [];

        var toAdd:Array<Array<Dynamic>> = [];
        var toAbstract:Array<Array<Dynamic>> = [];
        var toAlias:Array<Array<String>> = [];
        var toSuperClass:Array<Array<String>> = [];
        var toInterface:Array<Array<String>> = [];
        
        var currentPos = Context.currentPos();
        
        for (item in module) {
            switch (item) {
                case TInst(t, params):
                    // Type
                    var rawTypePath = t.toString();

                    // Workaround needed on haxe 4?
                    if (rawTypePath.startsWith('_Sys.')) continue;

                    // Compute sub type paths and alias
                    var alias = null;
                    var subTypePath = rawTypePath;
                    if (rawTypePath != typePath) {
                        subTypePath = typePath + rawTypePath.substring(rawTypePath.lastIndexOf('.'));
                        alias = [rawTypePath, subTypePath];
                    }

                    // Abstract implementation?
                    var abstractType = null;
                    if (rawTypePath.endsWith('_Impl_')) {
                        for (aType in abstractTypes) {
                            var implName = aType;
                            var dotIndex = implName.lastIndexOf('.');
                            if (dotIndex != -1) {
                                implName = implName.substring(0, dotIndex) + '._' + implName.substring(dotIndex + 1) + '.' + implName.substring(dotIndex + 1) + '_Impl_';
                            }
                            else {
                                implName = '_' + implName + '.' + implName + '_Impl_';
                            }
                            if (rawTypePath == implName) {
                                abstractType = aType;
                                break;
                            }
                        }

                        if (abstractType == null) {
                            continue;
                        }
                    }

                    if (abstractType != null) {
                        // Abstract implementation code
                        trace('ABSTRACT IMPL $abstractType');

                        for (field in t.get().statics.get()) {
    #if !interpret_keep_deprecated
                            if (field.meta.has(':deprecated')) continue;
    #end
                            if (!field.isPublic) continue;
                            trace('field: ' + field.name);

                            var metas = field.meta.get();
                            var hasImplMeta = false;
                            for (meta in metas) {
                                if (meta.name == ':impl') {
                                    hasImplMeta = true;
                                    break;
                                }
                            }
                            var isStatic = !hasImplMeta;

                            trace('   hasImpl: $hasImplMeta');
                            //trace('type: ' + field.type);
                            //trace(field);
                            switch (field.kind) {

                                case FMethod(k):
                                    switch (field.type) {
                                        case TFun(args, ret):
                                            var _args = [];
                                            var _ret = null;
                                            if (ret != null) {
                                                _ret = haxe.macro.TypeTools.toComplexType(ret);
                                            }
                                            for (arg in args) {

                                                var complexType = haxe.macro.TypeTools.toComplexType(arg.t);
                                                /*switch (complexType) {
                                                    case TPath(p):
                                                        trace('TPath: name=' + p.name + ' pack=' + p.pack + ' sub=' + p.sub);
                                                    default:
                                                }*/

                                                _args.push({
                                                    name: arg.name,
                                                    type: complexType,
                                                    opt: arg.opt,
                                                    value: null
                                                });
                                            }
                                            toAbstract.push([
                                                abstractType + '.' + field.name,
                                                ModuleItemKind.ABSTRACT_FUNC,
                                                _args, _ret,
                                                isStatic
                                            ]);
                                        default:
                                    }
                                case FVar(read, write):
                                    var readable = switch (read) {
                                        case AccNormal | AccCall | AccInline: true;
                                        default: false;
                                    }
                                    var writable = switch (write) {
                                        case AccNormal | AccCall: true;
                                        default: false;
                                    }
                                    if (isStatic) {
                                        // In that case, that's a static var access
                                        toAbstract.push([
                                            abstractType + '.' + field.name,
                                            ModuleItemKind.ABSTRACT_VAR,
                                            readable, writable
                                        ]);
                                    }
                                default:
                            }
                        } 
                    }
                    else {
                        // Regular class

                        // Add alias if any
                        if (alias != null) {
                            toAlias.push(alias);
                        }

                        var subTypePath = rawTypePath;
                        if (rawTypePath != typePath) {
                            subTypePath = typePath + rawTypePath.substring(rawTypePath.lastIndexOf('.'));
                            toAlias.push([rawTypePath, subTypePath]);
                        }
                        toAdd.push([subTypePath, ModuleItemKind.CLASS]);

                        // Superclass
                        var prevParent = t;
                        var parentHold = t.get().superClass;
                        var parent = parentHold != null ? parentHold.t : null;
                        while (parent != null) {
                            toSuperClass.push([prevParent.toString(), parent.toString()]);
                            parentHold = parent.get().superClass;
                            parent = parentHold != null ? parentHold.t : null;
                        }

                        // Interfaces
                        for (item in t.get().interfaces) {
                            toInterface.push([subTypePath, item.t.toString()]);
                        }

                        // Static fields
                        for (field in t.get().statics.get()) {
                            if (!field.isPublic) continue;
    #if !interpret_keep_deprecated
                            if (field.meta.has(':deprecated')) continue;
    #end
                            switch (field.kind) {
                                case FMethod(k):
                                    switch (field.type) {
                                        case TFun(args, ret):
                                            if (args.length > 0) {
                                                var extendedType:String = null;
                                                switch (args[0].t) {
                                                    case TInst(t, params):
                                                        extendedType = t.toString();
                                                    case TAbstract(t, params):
                                                        extendedType = t.toString();
                                                    default:
                                                }
                                                toAdd.push([
                                                    subTypePath + '.' + field.name,
                                                    ModuleItemKind.CLASS_FIELD,
                                                    extendedType
                                                ]);
                                            } else {
                                                toAdd.push([
                                                    subTypePath + '.' + field.name,
                                                    ModuleItemKind.CLASS_FIELD,
                                                    null
                                                ]);
                                            }
                                        default:
                                    }
                                default:
                                    toAdd.push([
                                        subTypePath + '.' + field.name,
                                        ModuleItemKind.CLASS_FIELD,
                                        null
                                    ]);
                            }
                        }
                    }
                
                case TEnum(t, params):
                    // Type
                    var rawTypePath = t.toString();
                    var subTypePath = rawTypePath;
                    if (rawTypePath != typePath) {
                        subTypePath = typePath + rawTypePath.substring(rawTypePath.lastIndexOf('.'));
                        toAlias.push([rawTypePath, subTypePath]);
                    }

                    toAdd.push([
                        subTypePath,
                        ModuleItemKind.ENUM,
                        null
                    ]);

                    for (item in t.get().constructs) {
                        switch (item.type) {
                            case TEnum(t, params):
                                toAdd.push([
                                    subTypePath + '.' + item.name,
                                    ModuleItemKind.ENUM_FIELD,
                                    -1
                                ]);
                            case TFun(args, ret):
                                /*var argNames = [];
                                for (arg in args) {
                                    argNames.push(arg.name);
                                }*/
                                toAdd.push([
                                    subTypePath + '.' + item.name,
                                    ModuleItemKind.ENUM_FIELD,
                                    args.length
                                ]);
                            default:
                        }
                    }
                case TAbstract(t, params):
                    // Type
                    var rawTypePath = t.toString();

                    var subTypePath = rawTypePath;
                    if (rawTypePath != typePath) {
                        subTypePath = typePath + rawTypePath.substring(rawTypePath.lastIndexOf('.'));
                        toAlias.push([rawTypePath, subTypePath]);
                    }
                    toAdd.push([subTypePath, ModuleItemKind.ABSTRACT]);

                    abstractTypes.push(subTypePath);

                    trace('ABSTRACT $t / $params');

                default:
            }
        }

        var addExprs:Array<Expr> = [];
        for (item in toAdd) {
            if (item[1] == ModuleItemKind.ABSTRACT) {
                var expr = macro mod.add($v{item[0]}, null, $v{item[1]}, $v{item[2]});
                addExprs.push(expr);
            }
            else {
                var expr = macro mod.add($v{item[0]}, $p{item[0].split('.')}, $v{item[1]}, $v{item[2]});
                addExprs.push(expr);
            }
        }
        var aliasExprs:Array<Expr> = [];
        for (item in toAlias) {
            var expr = macro module.alias($v{item[0]}, $v{item[1]});
            aliasExprs.push(expr);
        }
        var superClassExprs:Array<Expr> = [];
        for (item in toSuperClass) {
            var expr = macro module.addSuperClass($v{item[0]}, $v{item[1]});
            superClassExprs.push(expr);
        }
        var interfaceExprs:Array<Expr> = [];
        for (item in toInterface) {
            var expr = macro module.addInterface($v{item[0]}, $v{item[1]});
            interfaceExprs.push(expr);
        }

        var abstractExprs:Array<Expr> = [];
        for (item in toAbstract) {
            var fullName:String = item[0];
            var abstractType:String = fullName;
            var abstractName:String = fullName;
            var abstractPack = [];
            var name:String = fullName;
            var dotIndex = fullName.lastIndexOf('.');
            if (dotIndex != -1) {
                name = fullName.substring(dotIndex + 1);
                abstractType = fullName.substring(0, dotIndex);
                abstractName = abstractType;
                dotIndex = abstractType.lastIndexOf('.');
                if (dotIndex != -1) {
                    abstractName = abstractType.substring(dotIndex + 1);
                    abstractPack = abstractType.substring(0, dotIndex).split('.');
                }
            }
            if (item[1] == ModuleItemKind.ABSTRACT_FUNC) {
                var args:Array<FunctionArg> = item[2];
                var ret:ComplexType = item[3];
                var isStatic:Bool = item[4];
                var instanceArgs:Array<FunctionArg> = [].concat(args);
                var callArgs = [for (arg in args) macro $i{arg.name}];
                args = [{
                    name: '_hold',
                    type: macro :interpret.HoldValue,
                    opt: false,
                    value: null
                }].concat(args);
                if (!isStatic) {
                    instanceArgs.shift();
                    callArgs = [for (arg in instanceArgs) macro $i{arg.name}];
                }
                var isGetter = name.startsWith('get_');
                var isSetter = name.startsWith('set_');
                if (isGetter || isSetter) name = name.substring(4);

                var isVoidRet = false;
                if (ret == null) {
                    isVoidRet = true;
                }
                else {
                    switch (ret) {
                        case TPath(p):
                            if (p.name == 'Void') {
                                isVoidRet = true;
                            }
                        default:
                    }
                }

                if (!isStatic) {
                    var thisArg = args[1];
                    thisArg.name = '_this';
                    thisArg.type = TPath({
                        name: abstractName,
                        pack: abstractPack,
                        params: []
                    });
                }

                //trace('args: ' + args);
                /*var fnExpr0 = macro function(a:Int) {
                    
                };
                trace('fn0: ' + fnExpr0);*/
                /*var varExpr_ = macro var _this:ceramic.Color = this;
                trace('varExpr: $varExpr_');

                var varExpr = {
                    expr: EVars([{
                        expr: {
                            expr: EConst(CIdent('this')),
                            pos: currentPos,
                            name: '_this'
                        },
                        pos: currentPos
                    }]),
                    pos: currentPos
                }*/

                var fnBody = switch [isStatic, isVoidRet] {
                    case [true, true]: macro {
                        $p{item[0].split('.')}($a{callArgs});
                    };
                    case [true, false]: macro {
                        return $p{item[0].split('.')}($a{callArgs});
                    };
                    case [false, true]: macro {
                        $p{['_this', name]}($a{callArgs});
                        _hold.value = _this;
                    };
                    case [false, false]: macro {
                        var _res = $p{['_this', name]}($a{callArgs});
                        _hold.value = _this;
                        return _res;
                    };
                };

                var fnExpr = {
                    expr: EFunction(null, {
                        args: args,
                        expr: {
                            expr: fnBody.expr,
                            pos: pos
                        },
                        params: [],
                        ret: null
                    }),
                    pos: pos
                };
                //trace('fn: ' + fnExpr);
                var printer = new haxe.macro.Printer();
                trace('$name: ' + printer.printExpr(fnExpr));
                var expr = macro mod.add($v{item[0]}, $fnExpr, $v{item[1]}, null);
                abstractExprs.push(expr);
            }
            else { // ABSTRACT_VAR
                //trace('item[0]: ' + item[0]);
                var readable:Bool = item[2];
                var writable:Bool = item[3];
                if (readable) {
                    var expr = macro mod.add($v{item[0]}, function() {
                        return $p{item[0].split('.')};
                    }, $v{item[1]}, 0);
                    abstractExprs.push(expr);
                }
                if (writable) {
                    var expr = macro mod.add($v{item[0]}, function(value) {
                        return $p{item[0].split('.')} = value;
                    }, $v{item[1]}, 1);
                    abstractExprs.push(expr);
                }
            }
        }

        var result = macro (function() {
            var module = new interpret.DynamicModule();
            module.pack = $v{packString};
            $b{aliasExprs};
            $b{superClassExprs};
            $b{interfaceExprs};
            module.lazyLoad = function(mod) {
                $b{addExprs};
                $b{abstractExprs};
            }
            return module;
        })();

        //trace(new haxe.macro.Printer().printExpr(result));

        return result;

    } //fromStatic

/// Print

    public function toString() {

        return 'DynamicModule($typePath)';

    } //toString

} //DynamicModule
