# Toy Gaussian Splatting for iOS & Metal 

![Alt Text](media/demo.gif)

<img src="media/demo.gif" height="100">


## About 
A buggy + slow gaussian splat renderer for iOS + Metal. 
Based on / inspired by several existing projects:
- [Original Gaussian Splatting Repo](https://github.com/graphdeco-inria/gaussian-splatting/)
- [Unity Gaussian Splatting](https://github.com/aras-p/UnityGaussianSplatting)
- [WebGPU Gaussian Splatting from cvlab-epfl](https://github.com/cvlab-epfl/gaussian-splatting-web) 
- [MrNeRF gaussian splatting cuda](https://github.com/MrNeRF/gaussian-splatting-cuda)

- Uses [Satin + Forge](https://github.com/Hi-Rez/Satin) for AR / 3d views ( made by [@rezaali](https://twitter.com/RezaAli) )


Only tested on an iPhone 14 Pro. Older phones will probably struggle. You can adjust the render resolution when loading a model by increasing the rendererDownsample to 4x or more on the 'SplatModelInfo' struct. 


:warning: This was a quick weekend hack project for educational purposes. As such the code is bad.  



## TODO / Not Implemented 
- Spherical harmonics are not supported
- Sorting is done with std::sort on CPU
- Use depth matte from LiDAR sensor to occlude splats? 



## License(s)
Parts of the code are based on the original Gaussian-Splatting software and is governed by the [Gaussian-Splatting License](https://github.com/graphdeco-inria/gaussian-splatting/blob/main/LICENSE.md), which can be found in the [LICENSE]() file in this repository. The original software was developed by Inria and MPII.

Please be advised that the software in this repository cannot be used for commercial purposes without explicit consent from the original licensors, Inria and MPII.

[Satin + Forge](https://github.com/Hi-Rez/Satin) are released under the MIT license. See [LICENSE](https://github.com/Hi-Rez/Satin/blob/master/LICENSE) for details. 




## Models Attribution
Includs two models from the original NeRF synthetic blender dataset 

The renders are from modified blender models located on blendswap.com
drums by bryanajones (CC-BY): https://www.blendswap.com/blend/13383
ficus by Herberhold (CC-0): https://www.blendswap.com/blend/23125
lego by Heinzelnisse (CC-BY-NC): https://www.blendswap.com/blend/11490
mic by up3d.de (CC-0): https://www.blendswap.com/blend/23295
ship by gregzaal (CC-BY-SA): https://www.blendswap.com/blend/8167
