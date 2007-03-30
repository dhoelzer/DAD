<?php

function drawPercent($percent) {
   $image = ImageCreate(102,10);
   $back = ImageColorAllocate($image,255,255,255);
   $border = ImageColorAllocate($image,0,0,0);
   $red = ImageColorAllocate($image,255,60,75);
   $fill = ImageColorAllocate($image,44,81,150);
   ImageFilledRectangle($image,0,0,101,9,$back);
   ImageFilledRectangle($image,1,1,$percent,9,$fill);
   ImageRectangle($image,0,0,101,9,$border);
   imagePNG($image);
   imagedestroy($image);
}

Header("Content-type: image/png");
drawPercent($_GET['percent']);

?> 