import bpy, sys
out = sys.argv[sys.argv.index('--') + 1]
A = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
print('EXPORT', bpy.ops.export_scene.vrm(filepath=out, armature_object_name=A.name), out)
