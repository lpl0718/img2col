import numpy as np
import torch
import torch.nn as nn
M0 = 8
N0 = 8
K0 = C0 = 4

def ceil_div(x, y):
    return (x + y - 1) // y

def ceil_align(x, y):
    return ceil_div(x, y) * y



# NK -> K1NK0
def OCICKhKw2IC1KhKwOIC0(weight, out_channel, in_channel, kernel_h, kernel_w, oc_start, ic_start, oc_size, ic_size): #(Ci1KhKw)CoCi0
    assert(weight.shape[0] == out_channel)
    assert(weight.shape[1] == in_channel)
    assert(weight.shape[2] == kernel_h)
    assert(weight.shape[3] == kernel_w)
    C1 = ceil_div(ic_size, C0)
    weight_OCICKhKw = weight[oc_start:oc_start + oc_size, ic_start:ic_start + ic_size]
    weight_OCKhKwIC = weight_OCICKhKw.transpose((0, 2, 3, 1))
    weight_OCKhKwIC_ = np.zeros((oc_size, kernel_h, kernel_w, C1*C0))
    for ic in range(ic_size):
        weight_OCKhKwIC_[:, :, :, ic] = weight_OCKhKwIC[:, :, :, ic]
    weight_OCKhKwCc = weight_OCKhKwIC_.reshape((oc_size, kernel_h, kernel_w, C1, C0))
    weight_IC1KhKwOIC0 = weight_OCKhKwCc.transpose((3, 1, 2, 0, 4)).reshape((C1*kernel_h*kernel_w, oc_size, C0))
    return weight_IC1KhKwOIC0


def compare(tensor_test, tensor_golden, threshold = 0.01):
    diff = np.abs(tensor_test.flatten() - tensor_golden.flatten())
    error_rate = diff / (np.abs(tensor_golden.flatten()) + 1e-10)
    if error_rate.mean() < threshold:
        print("pass")
        return True
    else:
        print("fail, error rate: ", np.max(error_rate))
        return False


def K1NK02N1K1N0K0_L12RMB(matrix_k1nk0,    tile_n,      start_tile_n,      start_tile_k1,                        slice_n,   slice_k1):
#     (Ci1KhKw)CoCi0     (weight_k1nk0_l1, oc_size_l1, l0_oc_start_in_l1, l0_ci1_start_in_l1*kernel_h*kernel_w, l0_oc_size, l0_ci1_size*kernel_h*kernel_w)
    K1 = slice_k1
    N1 = ceil_div(slice_n, N0)
    assert(matrix_k1nk0.shape[1] == tile_n) #l0_oc_size
    matrix_n1k1n0k0 = np.zeros((N1, K1, N0, K0))
    for n1 in range(N1):
        for k1 in range(K1):
            for n0 in range(N0):
                n = n1 * N0 + n0
                if(n < slice_n):
                    matrix_n1k1n0k0[n1][k1][n0] = matrix_k1nk0[start_tile_k1+k1][start_tile_n+n]
    return matrix_n1k1n0k0

def N2N1N0_L12PMB(bias, start_n, tile_n):
    N1 = ceil_div(tile_n, N0)
    bias_N1N0 = np.zeros((N1, N0))
    for n1 in range(N1):
        for n0 in range(N0):
            n = n1 * N0 + n0
            if(n < tile_n):
                bias_N1N0[n1][n0] = bias[start_n+n]
    return bias_N1N0


def BHWC2C1BHWC0_DDR2L1(ifm, batch, tensor_h, tensor_w, tensor_c, start_tensor_h, start_tensor_w, start_tensor_c, tile_h, tile_w, tile_c):
    C1 = ceil_div(tile_c, C0)
    ifm_C1BHWC0 = np.zeros((C1, batch, tile_h, tile_w, C0))
    assert(ifm.shape[1] == tensor_h)
    assert(ifm.shape[2] == tensor_w)


    assert(ifm.shape[3] == tensor_c)
    for c1 in range(C1):
        for b in range(batch):
            for h in range(tile_h):
                for w in range(tile_w):
                    for c0 in range(C0):
                        c = c1 * C0 + c0
                        if(c < tile_c):
                            ifm_C1BHWC0[c1][b][h][w][c0] = ifm[b][h+start_tensor_h][w+start_tensor_w][c+start_tensor_c]
    return  ifm_C1BHWC0
    # return ifm_C1BHWC0.reshape((C1, batch, tile_h, tile_w, C0))#多余的

def C1BHWC02M1K1M0K0_L12L0(ifm, batch, slice_oh, slice_ow, slice_c1, start_tile_h, start_tile_w, start_tile_c1, kernel_h, kernel_w, stride_h, stride_w, pad_t, pad_b, pad_l, pad_r, dilation_h, dilation_w, padding_value=0):
    slice_ih = (slice_oh - 1) * stride_h + dilation_h * (kernel_h - 1) - pad_t - pad_b + 1
    slice_iw = (slice_ow - 1) * stride_w + dilation_w * (kernel_w - 1) - pad_l - pad_r + 1
    C1 = slice_c1
    M = batch * slice_oh * slice_ow
    M1 = ceil_div(M, M0)
    K1 = C1*kernel_h*kernel_w
    ifm_m1k1m0k0 = np.zeros((M1, K1, M0, K0))
    for ic1 in range(C1):
        for kh in range(kernel_h):
            for kw in range(kernel_w):
                for b in range(batch):
                    for oh in range(slice_oh):
                        for ow in range(slice_ow):
                            ih = kh * dilation_h - pad_t + oh * stride_h
                            iw = kw * dilation_w - pad_l + ow * stride_w
                            m_index = b*slice_oh*slice_ow + oh*slice_ow + ow
                            k1_idx = ic1 * kernel_h * kernel_w + kh * kernel_w + kw
                            m1_idx = m_index // M0
                            m0_idx = m_index % M0
                            if (0 <= ih < slice_ih) and (0 <= iw < slice_iw):
                                ifm_m1k1m0k0[m1_idx][k1_idx][m0_idx] = ifm[start_tile_c1 + ic1][b][start_tile_h + ih][start_tile_w + iw]
                            else:
                                for k0_idx in range(K0):
                                    ifm_m1k1m0k0[m1_idx][k1_idx][m0_idx][k0_idx] = padding_value
    return ifm_m1k1m0k0

def matmul_m1k1m0k0_n1k1n0k0(m1n1m0n0, m1k1m0k0, n1k1n0k0, bias_n1n0, deq_n1n0, M1, N1, K1, bias_en, psum_en, deq_en):
    assert(m1k1m0k0.shape[1] == n1k1n0k0.shape[1])
    assert(m1k1m0k0.shape[3] == n1k1n0k0.shape[3])
    for m1 in range(M1):
        for n1 in range(N1):
            temp = np.zeros((M0, N0))
            for k1 in range(K1):
                temp += np.matmul(m1k1m0k0[m1][k1], n1k1n0k0[n1][k1].transpose())
            if(bias_en):
                for n0 in range(N0):
                    temp[:, n0] += bias_n1n0[n1][n0]
            if(psum_en):
                m1n1m0n0[m1][n1] += temp
            else:
                m1n1m0n0[m1][n1] = temp
    if(deq_en):
        for n1 in range(N1):
            for n0 in range(N0):
                for m1 in range(M1):
                    for m0 in range(M0):
                        val = m1n1m0n0[m1][n1][m0][n0] * deq_n1n0[n1][n0]
                        if val>127:
                            val=127
                        elif val<0:
                            val=0
                        m1n1m0n0[m1][n1][m0][n0] =val
    return m1n1m0n0 

def M1N1M0N02BHWC_PSB2DDR(ofm_ddr, ofm_psb, batch, tensor_oh, tensor_ow, tensor_oc, start_tensor_oh, start_tensor_ow, start_tensor_oc, slice_oh, slice_ow, slice_oc):
    M = batch * slice_oh * slice_ow
    M1 = ceil_div(M, M0)
    N1 = ceil_div(slice_oc, N0)
    assert(ofm_ddr.shape[1] == tensor_oh)
    assert(ofm_ddr.shape[2] == tensor_ow)
    assert(ofm_ddr.shape[3] == tensor_oc)
    for m1 in range(M1):
        for n1 in range(N1):
            for m0 in range(M0):
                for n0 in range(N0):
                    m = m1 * M0 + m0
                    n = n1 * N0 + n0
                    b = m // (slice_oh * slice_ow)
                    oh = (m % (slice_oh * slice_ow)) // slice_ow
                    ow = (m % (slice_oh * slice_ow)) % slice_ow
                    if(b < batch and oh < slice_oh and ow < slice_ow and n < slice_oc):
                            ofm_ddr[b][start_tensor_oh + oh][start_tensor_ow + ow][start_tensor_oc + n] = ofm_psb[m1][n1][m0][n0]
    return ofm_ddr

