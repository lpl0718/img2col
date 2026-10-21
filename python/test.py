from convolution import *
import unittest
import numpy as np
import torch
import torch.nn as nn

def generate_convolutions_params():
    out_height, out_width = 0, 0
    # while(out_height < 3 or out_width < 3):
    #     batch = np.random.randint(1, 4)
    #     in_height = np.random.randint(3, 100)
    #     in_width = np.random.randint(3, 100)
    #     in_channel = np.random.randint(3, 100)
    #     out_channel = np.random.randint(3, 100)
    #     kernel_h = np.random.randint(1,7)
    #     kernel_w = np.random.randint(1,7)
    #     stride_h = np.random.randint(1,7)
    #     stride_w = np.random.randint(1,7)
    #     pad_h = np.random.randint(0, kernel_h)
    #     pad_w = np.random.randint(0, kernel_w)
    #     dilation_h = np.random.randint(1,7)
    #     dilation_w = np.random.randint(1,7)
    #     out_height = (in_height + 2 * pad_h - dilation_h * (kernel_h - 1) - 1) // stride_h + 1
    #     out_width = (in_width + 2 * pad_w - dilation_w * (kernel_w - 1) - 1) // stride_w + 1
    while(out_height < 3 or out_width < 3):
        batch = 1
        in_height = 36
        in_width = 64
        in_channel = 3
        out_channel =  8

        kernel_h = 3
        kernel_w = 3
        stride_h = 1
        stride_w = 1

        dilation_h = 1
        dilation_w = 1
        pad_h = 1
        pad_w = 1
        out_height = (in_height + 2 * pad_h - dilation_h * (kernel_h - 1) - 1) // stride_h + 1
        out_width = (in_width + 2 * pad_w - dilation_w * (kernel_w - 1) - 1) // stride_w + 1

    conv_params = {
    'batch': batch,
    'in_height': in_height,
    'in_width': in_width,
    'out_height': out_height,
    'out_width': out_width,
    'in_channel': in_channel,
    'out_channel': out_channel,
    'kernel_h': kernel_h,
    'kernel_w': kernel_w,
    'stride_h': stride_h,
    'stride_w': stride_w,
    'pad_h': pad_h,
    'pad_w': pad_w,
    'dilation_h': dilation_h,
    'dilation_w': dilation_w
    }
    return conv_params

class BlockTestConvolution(unittest.TestCase):
    def setUp(self):
        print("="*100)
        print("BlockTestConvolution begin")

    def test_convolution_full(self):
        print("test_convolution_full")
        for i in range(3):
            conv_params = generate_convolutions_params()
            print(conv_params)
            ifm_BCHW = np.random.randn(conv_params['batch'], conv_params['in_channel'], conv_params['in_height'], conv_params['in_width']).astype(np.float32)
            weight = np.random.randn(conv_params['out_channel'], conv_params['in_channel'], conv_params['kernel_h'], conv_params['kernel_w']).astype(np.float32)
            bias = np.random.randn(conv_params['out_channel']).astype(np.float32)
            deq = np.random.randn(conv_params['out_channel']).astype(np.float32)
            ifm_torch = torch.tensor(ifm_BCHW, dtype=torch.float32)
            weight_torch = torch.tensor(weight, dtype=torch.float32)
            bias_torch = torch.tensor(bias, dtype=torch.float32)
            deq_torch = torch.tensor(deq, dtype=torch.float32)
            ofm_torch = nn.functional.conv2d(ifm_torch, weight_torch, bias_torch, stride=(conv_params['stride_h'], conv_params['stride_w']), \
                                             padding=(conv_params['pad_h'], conv_params['pad_w']), dilation=(conv_params['dilation_h'], conv_params['dilation_w']))
            ofm_torch = ofm_torch * deq_torch.view(1, -1, 1, 1)

            ofm_torch = torch.clamp(ofm_torch, min=0, max=127)
            ifm_BHWC = ifm_BCHW.transpose((0, 2, 3, 1))
            ofm_BHWC = op_convolution_full(conv_params, ifm_BHWC, weight, bias, deq)
            ofm_BCHW = ofm_BHWC.reshape((conv_params['batch'], conv_params['out_height'], conv_params['out_width'], conv_params['out_channel'])).transpose((0, 3, 1, 2))
            test_pass = compare(ofm_BCHW.flatten(), ofm_torch.numpy().flatten())
            self.assertEqual(test_pass, True)



    def tearDown(self):
        print("BlockTestConvolution end")
        print("="*100)


if __name__ == "__main__":
    unittest.main()