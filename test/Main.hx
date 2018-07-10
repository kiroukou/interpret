package test;

// TODO handle inheritance to parent native class
// TODO handle inheritance to parent dynamic class
// TODO add DynamicEnum support

// TODO convert arrow functions () -> { }
// TODO convert combined switches switch [a, b] { case [_, 'something']: ... }

// TODO convert haxe code into DynamicModule instead of DynamicClass
// TODO use DynamicModule instances to get classes and enums, just like in regular Haxe
//      - add DynamicModule.fromFile('some/haxe/File.hx')
//      - add DynamicModule.fromString('... some haxe string ...')

import sys.io.File;
import hxs.DynamicClass;
import hxs.ConvertHaxe;
import hxs.Env;
import hxs.DynamicExtension;
import hxs.DynamicModule;

import haxe.io.Path;

import hxs.ExtensionTest;

class Main {

    public static function main() {

#if js
        try {
            untyped require('source-map-support').install();
        } catch (e:Dynamic) {}
#end

/*
        trace('PARSE');

        var nativeObj = new SomeClass('Jérémy');
        nativeObj.hello();

        var content = File.getContent('scripting/SomeClassCleaned.hx');
        var parser = new hscript.Parser();
        parser.allowJSON = true;
        parser.allowMetadata = true;
        parser.allowTypes = true;
        var program = parser.parseString(content);
        var interp = new hxs.Interp();

        trace('EXEC');
        interp.execute(program);

        var _new = interp.variables.get('new');
        var hello = interp.variables.get('hello');

        _new('Jon Doe');

        hello();

        interp.variables.set('name', 'Pierrot');

        hello();

        return;
        //*/

        // Load haxe content
        var content = File.getContent('scripting/SomeClass.hx');

        // Create env
        var env = new Env();
        //env.allowPackage('hxs');

        env.addModule('hxs.ImportTest', DynamicModule.fromStatic(hxs.ImportTest));

        // Expose StringTools static extension
        env.addExtension('StringTools', DynamicExtension.fromStatic(StringTools));

        // Create dynamic class from env and haxe content
        var dynClass = new DynamicClass(env, content);

        // Print some static property from this class
        //trace(dynClass.get('someStaticProperty'));

        // Create instance
        var dynInstance = dynClass.createInstance();

        // Call instance method
        //dynInstance.get('someInstanceMethod')('some', 'args');

        //hxs.ImportTest.SomeOtherType.hi();
        












        //env.extensions.set('Extensions', DynamicExtension.fromStatic(ceramic.Extensions));
/*
        var dynClass = new DynamicClass(env, content);

        trace(dynClass.instanceHscript);
        //trace(dynClass.classHscript);

        trace('lastName: ' + dynClass.get('lastName'));
        trace('_defaultName: ' + dynClass.get('defaultNamee'));*/

        /*for (i in 0...10) {
            trace('dummy2: ' + dynClass.get('dummy2')());
        }*/

        /*var dynObj = dynClass.createInstance();
        trace('obj.name = ' + dynObj.get('name'));
        trace('obj.lastName = ' + dynObj.get('lastName'));*/

    } //main

} //Main
