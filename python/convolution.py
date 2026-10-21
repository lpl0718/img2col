from lib import *

def op_convolution_full(conv_params, ifm, weight, bias, deq, zero_point=0):
    batch = conv_params['batch']
    in_height = conv_params['in_height']
    in_width = conv_params['in_width']
    out_height = conv_params['out_height']
    out_width = conv_params['out_width']
    in_channel = conv_params['in_channel']
    out_channel = conv_params['out_channel']
    kernel_h = conv_params['kernel_h']
    kernel_w = conv_params['kernel_w']
    stride_h = conv_params['stride_h']
    stride_w = conv_params['stride_w']
    pad_h = conv_params['pad_h']
    pad_w = conv_params['pad_w']
    dilation_h = conv_params['dilation_h']
    dilation_w = conv_params['dilation_w']

    # H_L1 = np.random.randint(2, out_height)
    # W_L1 = np.random.randint(2, out_width)
    # CI_L1 = np.random.randint(2, in_channel)
    # CO_L1 = ceil_align(np.random.randint(1, out_channel), N0)
    # H_L0 = np.random.randint(1, H_L1)
    # W_L0 = np.random.randint(1, W_L1)
    # CI1_L0 = ceil_div(np.random.randint(1, CI_L1), K0)
    # CO_L0 = ceil_align(np.random.randint(1, CO_L1), N0)

    H_L1 = 18
    W_L1 = 32
    CI_L1 = 4
    CO_L1 = 4

    H_L0 = 9
    W_L0 = 16
    CI1_L0 = 4
    CO_L0 = 4
    # 定义卷积层参数
    tiling_params = {
    'CO_L1': CO_L1,
    'H_L1': H_L1,
    'W_L1': W_L1,
    'CI_L1': CI_L1,
    'CO_L0': CO_L0,
    'H_L0': H_L0,
    'W_L0': W_L0,
    'CI1_L0': CI1_L0
    }
    print(tiling_params)
    ofm_BHWC = np.zeros((batch, out_height, out_width, out_channel))

    for l1_oc_start_in_l2 in range(0, out_channel, CO_L1):
        for l1_oh_start_in_l2 in range(0, out_height, H_L1):
            for l1_ow_start_in_l2 in range(0, out_width, W_L1):
                oc_size_l1 = min(CO_L1, out_channel - l1_oc_start_in_l2)
                oh_size_l1 = min(H_L1, out_height - l1_oh_start_in_l2)
                ow_size_l1 = min(W_L1, out_width - l1_ow_start_in_l2)
                M = batch * H_L0 * W_L0
                N = oc_size_l1
                M1 = ceil_div(M, M0)
                N1 = ceil_div(N, N0)
                result_m2n2m1n1m0n0_psb = np.zeros((ceil_div(oh_size_l1, H_L0)*ceil_div(ow_size_l1, W_L0)*ceil_div(oc_size_l1, CO_L0), M1, N1, M0, N0))
                for l1_ic_start_in_l2 in range(0, in_channel, CI_L1):
                    l1_oh_end_in_l2 = min(l1_oh_start_in_l2 + H_L1, out_height) - 1
                    l1_ow_end_in_l2 = min(l1_ow_start_in_l2 + W_L1, out_width) - 1
                    l1_ih_start_in_l2 = max(l1_oh_start_in_l2 * stride_h - pad_h, 0)
                    l1_iw_start_in_l2 = max(l1_ow_start_in_l2 * stride_w - pad_w, 0)
                    l1_ih_end_in_l2 = min(l1_oh_end_in_l2 * stride_h - pad_h + dilation_h * (kernel_h - 1), in_height - 1)
                    l1_iw_end_in_l2 = min(l1_ow_end_in_l2 * stride_w - pad_w + dilation_w * (kernel_w - 1), in_width - 1)
                    l1_ic_end_in_l2 = min(l1_ic_start_in_l2 + CI_L1, in_channel) - 1
                    ih_size_l1 = l1_ih_end_in_l2 - l1_ih_start_in_l2 + 1
                    iw_size_l1 = l1_iw_end_in_l2 - l1_iw_start_in_l2 + 1
                    ic_size_l1 = l1_ic_end_in_l2 - l1_ic_start_in_l2 + 1
                    ci1_size_l1 = ceil_div(ic_size_l1, K0)
                    ifm_C1BHWC0_l1 = BHWC2C1BHWC0_DDR2L1(ifm, batch, in_height, in_width, in_channel, l1_ih_start_in_l2, l1_iw_start_in_l2, l1_ic_start_in_l2, ih_size_l1, iw_size_l1, ic_size_l1)
                    weight_k1nk0_l1 = OCICKhKw2IC1KhKwOIC0(weight, out_channel, in_channel, kernel_h, kernel_w, l1_oc_start_in_l2, l1_ic_start_in_l2, oc_size_l1, ic_size_l1) #     (Ci1KhKw)CoCi0
                    for l0_oc_start_in_l1 in range(0, oc_size_l1, CO_L0):
                        for l0_oh_start_in_l1 in range(0, oh_size_l1, H_L0):
                            for l0_ow_start_in_l1 in range(0, ow_size_l1, W_L0):
                                for l0_ci1_start_in_l1 in range(0, ci1_size_l1, CI1_L0): #ci1_size_l1, CI1_L0 都是K0的整数倍
                                    l0_oc_start_in_l2 = l1_oc_start_in_l2 + l0_oc_start_in_l1
                                    l0_oh_start_in_l2 = l1_oh_start_in_l2 + l0_oh_start_in_l1
                                    l0_ow_start_in_l2 = l1_ow_start_in_l2 + l0_ow_start_in_l1
                                    l0_oh_end_in_l2 = min(l0_oh_start_in_l2 + H_L0, l1_oh_start_in_l2 + oh_size_l1) - 1
                                    l0_ow_end_in_l2 = min(l0_ow_start_in_l2 + W_L0, l1_ow_start_in_l2 + ow_size_l1) - 1
                                    l0_ih_start_in_l2 = max(l0_oh_start_in_l2 * stride_h - pad_h, 0)
                                    l0_iw_start_in_l2 = max(l0_ow_start_in_l2 * stride_w - pad_w, 0)
                                    l0_ih_end_in_l2 = min(l0_oh_end_in_l2 * stride_h - pad_h + dilation_h * (kernel_h - 1), in_height - 1)
                                    l0_iw_end_in_l2 = min(l0_ow_end_in_l2 * stride_w - pad_w + dilation_w * (kernel_w - 1), in_width - 1)
                                    l0_ih_start_in_l1 = l0_ih_start_in_l2 - l1_ih_start_in_l2
                                    l0_ih_end_in_l1 = l0_ih_end_in_l2 - l1_ih_start_in_l2
                                    l0_iw_start_in_l1 = l0_iw_start_in_l2 - l1_iw_start_in_l2
                                    l0_iw_end_in_l1 = l0_iw_end_in_l2 - l1_iw_start_in_l2
                                    l0_iw_size = l0_iw_end_in_l1 - l0_iw_start_in_l1 + 1
                                    l0_ih_size = l0_ih_end_in_l1 - l0_ih_start_in_l1 + 1
                                    l0_ow_size = l0_ow_end_in_l2 - l0_ow_start_in_l2 + 1
                                    l0_oh_size = l0_oh_end_in_l2 - l0_oh_start_in_l2 + 1
                                    l0_ci1_size = min(ci1_size_l1 - l0_ci1_start_in_l1, CI1_L0)
                                    l0_oc_size = min(oc_size_l1 - l0_oc_start_in_l1, CO_L0)
                                    if(l0_oh_start_in_l2 * stride_h - pad_h < 0):
                                        l0_pad_t = pad_h - l0_oh_start_in_l2 * stride_h
                                    else:
                                        l0_pad_t = 0
                                    if(l0_oh_end_in_l2 * stride_h - pad_h + dilation_h * (kernel_h - 1) >= in_height):
                                        l0_pad_b = l0_oh_end_in_l2 * stride_h - pad_h + dilation_h * (kernel_h - 1) - in_height + 1
                                    else:
                                        l0_pad_b = 0
                                    if(l0_ow_start_in_l2 * stride_w - pad_w < 0):
                                        l0_pad_l = pad_w - l0_ow_start_in_l2 * stride_w
                                    else:
                                        l0_pad_l = 0
                                    if(l0_ow_end_in_l2 * stride_w - pad_w + dilation_w * (kernel_w - 1) >= in_width):
                                        l0_pad_r = l0_ow_end_in_l2 * stride_w - pad_w + dilation_w * (kernel_w - 1) - in_width + 1
                                    else:
                                        l0_pad_r = 0
                                    bias_en = (l1_ic_start_in_l2==0) and (l0_ci1_start_in_l1==0)
                                    psum_en = (l1_ic_start_in_l2 > 0) or (l0_ci1_start_in_l1 > 0)
                                    # deq_en = (l1_ic_start_in_l2 // CI_L1 == ceil_div(in_channel, CI_L1) - 1) and (l0_ci1_start_in_l1 // CI1_L0 == ceil_div(ci1_size_l1, CI1_L0) - 1)
                                    deq_en = (in_channel-l1_ic_start_in_l2 <= CI_L1) and (ci1_size_l1 - l0_ci1_start_in_l1 <=CI1_L0 )
                                    ifm_M1K1M0K0 = C1BHWC02M1K1M0K0_L12L0(ifm_C1BHWC0_l1, batch, l0_oh_size, l0_ow_size, l0_ci1_size, l0_ih_start_in_l1, l0_iw_start_in_l1, l0_ci1_start_in_l1, kernel_h, kernel_w, stride_h, stride_w, l0_pad_t, l0_pad_b, l0_pad_l, l0_pad_r, dilation_h, dilation_w, zero_point)
                                    weight_N1K1N0K0_l0 = K1NK02N1K1N0K0_L12RMB(weight_k1nk0_l1, oc_size_l1, l0_oc_start_in_l1, l0_ci1_start_in_l1*kernel_h*kernel_w, l0_oc_size, l0_ci1_size*kernel_h*kernel_w)
                                    bias_N1N0 = N2N1N0_L12PMB(bias, l0_oc_start_in_l2, l0_oc_size)
                                    deq_N1N0 = N2N1N0_L12PMB(deq, l0_oc_start_in_l2, l0_oc_size)
                                    psb_addr = l0_oh_start_in_l1//H_L0 * ceil_div(ow_size_l1, W_L0) * ceil_div(oc_size_l1, CO_L0) + l0_ow_start_in_l1//W_L0 * ceil_div(oc_size_l1, CO_L0) + l0_oc_start_in_l1//CO_L0
                                    # psb_addr = ((l0_oc_start_in_l1 // CO_L0) * ceil_div(oh_size_l1, H_L0) * ceil_div(ow_size_l1, W_L0)
                                    #             + (l0_oh_start_in_l1 // H_L0) * ceil_div(ow_size_l1, W_L0)
                                    #             + (l0_ow_start_in_l1 // W_L0))
                                    result_m2n2m1n1m0n0_psb[psb_addr] = matmul_m1k1m0k0_n1k1n0k0(\
                                    result_m2n2m1n1m0n0_psb[psb_addr], ifm_M1K1M0K0, weight_N1K1N0K0_l0, bias_N1N0, deq_N1N0, ifm_M1K1M0K0.shape[0], weight_N1K1N0K0_l0.shape[0], ifm_M1K1M0K0.shape[1], bias_en, psum_en, deq_en)
                                    if(deq_en):
                                        ofm_BHWC = M1N1M0N02BHWC_PSB2DDR(ofm_BHWC, result_m2n2m1n1m0n0_psb[psb_addr], batch, out_height, out_width, out_channel, l0_oh_start_in_l2, l0_ow_start_in_l2, l0_oc_start_in_l2, l0_oh_size, l0_ow_size, l0_oc_size)
    return ofm_BHWC

