import bpy, sys
a = sys.argv[sys.argv.index('--') + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.preferences.addon_enable(module='bl_ext.user_default.vrm')
print('IMPORT', bpy.ops.import_scene.vrm(filepath=a[0]))
print('OBJECTS', [o.name for o in bpy.data.objects])
bpy.ops.wm.save_as_mainfile(filepath=a[1])
