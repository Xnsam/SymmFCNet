
--[[
    This data loader is a modified version of the one from dcgan.torch
    (see https://github.com/soumith/dcgan.torch/blob/master/data/donkey_folder.lua).
    Copyright (c) 2016, Deepak Pathak [See LICENSE file for details]
    Copyright (c) 2015-present, Facebook, Inc.
    All rights reserved.
    This source code is licensed under the BSD-style license found in the
    LICENSE file in the root directory of this source tree. An additional grant
    of patent rights can be found in the PATENTS file in the same directory.
]]--

require 'image'
paths.dofile('dataset.lua')
-- This file contains the data-loading logic and details.
-- It is run by each data-loader thread.
------------------------------------------
-------- COMMON CACHES and PATHS
-- Check for existence of opt.data

if opt.DATA_ROOT then
  opt.data=paths.concat(opt.DATA_ROOT, opt.phase)
else

  opt.data=paths.concat(os.getenv('DATA_ROOT'), opt.phase)
end

if not paths.dirp(opt.data) then
    error('Did not find directory: ' .. opt.data)
end

-- a cache file of the training metadata (if doesnt exist, will be created)
local cache = "cache"
local cache_prefix = opt.data:gsub('/', '_')
os.execute('mkdir -p cache')
local trainCache = paths.concat(cache, cache_prefix .. '_trainCache.t7')

--------------------------------------------------------------------------------------------
local input_nc = opt.input_nc -- input channels
local output_nc = opt.output_nc
local loadSize   = {input_nc/3, opt.loadSize}
local sampleSize = {input_nc/3, opt.fineSize}





local preprocessABandLandmarks = function(imA, imB,path)
  imA = image.scale(imA, loadSize[2], loadSize[2])--1 放大到loadSize尺寸
  imB = image.scale(imB, loadSize[2], loadSize[2])
  local perm = torch.LongTensor{3, 2, 1}
  --这里把范围从-1到1 改为0到1
  imA = imA:index(1, perm)--:mul(256.0): brg, rgb
  -- imA = imA:mul(2):add(-1) 
  imB = imB:index(1, perm)
  -- imB = imB:mul(2):add(-1)

  assert(imA:max()<=1,"A: badly scaled inputs")
  assert(imA:min()>=0,"A: badly scaled inputs")
  assert(imB:max()<=1,"B: badly scaled inputs")
  assert(imB:min()>=0,"B: badly scaled inputs")

  local oW = sampleSize[2]
  local oH = sampleSize[2]
  local iH = imA:size(2)
  local iW = imA:size(3)
  
  if iH~=oH then     
    h1 = math.ceil(torch.uniform((iH-oH)/3, iH-oH))
  else
    h1 = 1
  end
  
  if iW~=oW then
    w1 = math.ceil(torch.uniform((iH-oH)/3, iW-oW))
  else
    w1 = 1
  end
  
  if iH ~= oH or iW ~= oW then 

    imA = image.crop(imA, w1, h1, w1 + oW, h1 + oH) 
    imB = image.crop(imB, w1, h1, w1 + oW, h1 + oH)

  end
  
  
  local flip_flag=0
  if opt.flip == 1    then -- 
    imA = image.hflip(imA)
    imB = image.hflip(imB)
    flip_flag=1
  end


  local PartLocation=torch.zeros(12)
  PartLocation:mul(loadSize[2]/sampleSize[2])


  local imAOri = imA:clone()
  
  local noise = torch.rand(imA:size()):typeAs(imA)
  local NoiseMask = torch.Tensor(1,oW,oW):zero() 
  local NoiseMaskFlip = torch.Tensor(1,oW,oW):zero() 
  local NoiseMaskNoGaussian = torch.Tensor(1,oW,oW):zero() -- 
  local NoiseMaskFlipNoGaussian = torch.Tensor(1,oW,oW):zero() -- 

  imA = imA:cmul(1-imB)+noise:cmul(imB)

  NoiseMask:copy(imB[{{1},{},{}}])
  NoiseMaskNoGaussian=NoiseMask:clone()
  local filterG = image.gaussian(7,3,1,true)
  kernel = torch.Tensor(9,9):fill(1)

  ---
  NoiseMask[1] = image.dilate(NoiseMask[1],kernel)
  NoiseMask[1] = image.convolve(NoiseMask[1],filterG,'same')
  NoiseMaskFlip = image.hflip(NoiseMask)
  NoiseMaskFlipNoGaussian = image.hflip(NoiseMaskNoGaussian)
  -- imA[{{},{SX,OutMaxX-1},{SY,OutMaxY-1}}]:fill(0)
  local imAhflip = image.hflip(imA) --image symmetry image

  local PointGroundtruth = torch.Tensor(2,oW,oW):zero()  
  local PointMask = torch.Tensor(1,oW,oW):zero()
  local PointMaskImg = torch.Tensor(1,oW,oW):zero()
  
  local flagPartsUpdate = torch.Tensor(4):fill(1) --
  

  return imAOri, imA,imAhflip, imB,PointGroundtruth,PointMask,PointMaskImg,NoiseMask,NoiseMaskFlip,NoiseMaskNoGaussian,NoiseMaskFlipNoGaussian,flip_flag,PartLocation,flagPartsUpdate --
end

function deprocess_lxm(img)
  -- BGR to RGB
  local perm = torch.LongTensor{3, 2, 1}
  img = img:index(1, perm)
  
  -- [-1,1] to [0,1]
  -- 这里也改了，直接时0到1
  -- img = img:add(1):div(2)
  
  return img
end
local function saveImgAndPoints(img,points)

end
local function loadImageChannel(path)
    local input = image.load(path, 3, 'float')
    input = image.scale(input, loadSize[2], loadSize[2])

    local oW = sampleSize[2]
    local oH = sampleSize[2]
    local iH = input:size(2)
    local iW = input:size(3)
    
    if iH~=oH then     
      h1 = math.ceil(torch.uniform(1e-2, iH-oH))
    end
    
    if iW~=oW then
      w1 = math.ceil(torch.uniform(1e-2, iW-oW))
    end
    if iH ~= oH or iW ~= oW then 
      input = image.crop(input, w1, h1, w1 + oW, h1 + oH)
    end
    
    
    if opt.flip == 1 and torch.uniform() > 0.5 then 
      input = image.hflip(input)
    end
    
--    print(input:mean(), input:min(), input:max())
    local input_lab = image.rgb2lab(input)
--    print(input_lab:size())
--    os.exit()
    local imA = input_lab[{{1}, {}, {} }]:div(50.0) - 1.0
    local imB = input_lab[{{2,3},{},{}}]:div(110.0)
    
    local imAB = torch.cat(imA, imB, 1)
    assert(imAB:max()<=1,"A: badly scaled inputs")
    assert(imAB:min()>=-1,"A: badly scaled inputs")
    
    return imAB
end

--local function loadImage

local function loadImage(path)
   local input = image.load(path, 3, 'float')
   local h = input:size(2)
   local w = input:size(3)

   local imA = image.crop(input, 0, 0, w/2, h)
   local imB = image.crop(input, w/2, 0, w, h)
   
   return imA, imB
end

local function loadImageInpaint(path)
  local imB = image.load(path, 3, 'float')
  imB = image.scale(imB, loadSize[2], loadSize[2])
  local perm = torch.LongTensor{3, 2, 1}
  imB = imB:index(1, perm)--:mul(256.0): brg, rgb
  imB = imB:mul(2):add(-1)
  assert(imB:max()<=1,"A: badly scaled inputs")
  assert(imB:min()>=-1,"A: badly scaled inputs")
  local oW = sampleSize[2]
  local oH = sampleSize[2]
  local iH = imB:size(2)
  local iW = imB:size(3)
  if iH~=oH then     
    h1 = math.ceil(torch.uniform(1e-2, iH-oH))
  end
  
  if iW~=oW then
    w1 = math.ceil(torch.uniform(1e-2, iW-oW))
  end
  if iH ~= oH or iW ~= oW then 
    imB = image.crop(imB, w1, h1, w1 + oW, h1 + oH)
  end
  local imA = imB:clone()
  imA[{{},{1 + oH/4, oH/2 + oH/4},{1 + oW/4, oW/2 + oW/4}}] = 1.0
  if opt.flip == 1 and torch.uniform() > 0.5 then 
    imA = image.hflip(imA)
    imB = image.hflip(imB)
  end
  imAB = torch.cat(imA, imB, 1)
  return imAB
end

-- channel-wise mean and std. Calculate or load them from disk later in the script.
local mean,std
--------------------------------------------------------------------------------
-- Hooks that are used for each image that is loaded

-- function to load the image, jitter it appropriately (random crops etc.)
local trainHook = function(self, path)
  collectgarbage()
  if opt.preprocess == 'regular' then

    local imA, imB = loadImage(path)
    local imGroundtruth, imAhflip, PointGroundtruth, PointMask,PointMaskImg,NoiseMask,NoiseMaskFlip,NoiseMaskNoGaussian,NoiseMaskFlipNoGaussian
    --  imA, imB,flip_flag = preprocessAandBC(imA, imB) 
    imGroundtruth, imA, imAhflip,imB, PointGroundtruth,PointMask,PointMaskImg,NoiseMask,NoiseMaskFlip,NoiseMaskNoGaussian,NoiseMaskFlipNoGaussian,flip_flag,location,flagPartsUpdate = preprocessABandLandmarks(imA, imB,path)
    imAB = torch.cat({imA, imAhflip, imB, imGroundtruth, PointGroundtruth, PointMask,PointMaskImg,NoiseMask,NoiseMaskFlip,NoiseMaskNoGaussian,NoiseMaskFlipNoGaussian}, 1) -- 3 3 3 3 2 1

    --
  end
  return imAB,flip_flag,location,flagPartsUpdate
end

--------------------------------------
-- trainLoader
print('trainCache', trainCache)
--if paths.filep(trainCache) then
--   print('Loading train metadata from cache')
--   trainLoader = torch.load(trainCache)
--   trainLoader.sampleHookTrain = trainHook
--   trainLoader.loadSize = {input_nc, opt.loadSize, opt.loadSize}
--   trainLoader.sampleSize = {input_nc+output_nc, sampleSize[2], sampleSize[2]}
--   trainLoader.serial_batches = opt.serial_batches
--   trainLoader.split = 100
--else
print('Creating train metadata')
--   print(opt.data)
print('serial batch:, ', opt.serial_batches)
trainLoader = dataLoader{
    paths = {opt.data},
    loadSize = {input_nc, loadSize[2], loadSize[2]},
    sampleSize = {input_nc+output_nc, sampleSize[2], sampleSize[2]},
    split = 100,
    serial_batches = opt.serial_batches, 
    verbose = true
 }
--   print('finish')
--torch.save(trainCache, trainLoader)
--print('saved metadata cache at', trainCache)
trainLoader.sampleHookTrain = trainHook

--end
collectgarbage()

-- do some sanity checks on trainLoader
do
   local class = trainLoader.imageClass
   local nClasses = #trainLoader.classes
   assert(class:max() <= nClasses, "class logic has error")
   assert(class:min() >= 1, "class logic has error")
end
