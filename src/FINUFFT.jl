__precompile__()
module FINUFFT

## Export
export nufft1d1, nufft1d2, nufft1d3
export nufft2d1, nufft2d2, nufft2d3
export nufft3d1, nufft3d2, nufft3d3

export nufft1d1!, nufft1d2!, nufft1d3!
export nufft2d1!, nufft2d2!, nufft2d3!
export nufft3d1!, nufft3d2!, nufft3d3!

export nufftf1d1!, nufftf1d2!, nufftf1d3!
export nufftf2d1!, nufftf2d2!, nufftf2d3!
export nufftf3d1!, nufftf3d2!, nufftf3d3!

export finufft_default_opts
export nufft_opts
export nufft_c_opts # backward-compability

## External dependencies
using finufft_jll

const libfinufft = finufft_jll.libfinufft

const BIGINT = Int64 # defined in src/finufft.h



## FINUFFT opts struct from src/finufft.h
"""
    mutable struct nufft_opts    
        modeord             :: Cint
        chkbnds             :: Cint              
        debug               :: Cint                
        spread_debug        :: Cint         
        showwarn            :: Cint
        nthreads            :: Cint
        fftw                :: Cint                 
        spread_sort         :: Cint          
        spread_kerevalmeth  :: Cint   
        spread_kerpad       :: Cint        
        upsampfac           :: Cdouble         
        spread_thread       :: Cint
        maxbatchsize        :: Cint
        spread_nthr_atomic  :: Cint
        spread_max_sp_size  :: Cint
    end

Options struct passed to the FINUFFT library.

# Fields

## Data handling opts

    modeord :: Cint 

(type 1,2 only):    0: CMCL-style increasing mode order,
                    1: FFT-style mode order

    chkbnds :: Cint
    
0: don't check NU pts in [-3pi,3pi),
1: do (<few % slower)

## Diagnostic opts

    debug :: Cint

0: silent,
1: some timing/debug,
2: more

    spread_debug :: Cint

0: silent,
1: some timing/debug,
2: tonnes

    showwarn :: Cint

0: don't print warnings to stderr,
1: do


## Algorithm performance opts

    nthreads :: Cint

number of threads to use, or 0 uses all available

    fftw :: Cint

plan flags to FFTW (`FFTW_ESTIMATE`=64, `FFTW_MEASURE`=0,...)

    spread_sort :: Cint

0: don't sort,
1: do,
2: heuristic choice

    spread_kerevalmeth :: Cint

0: exp(sqrt()) spreading kernel,
1: Horner piecewise poly (faster)

    spread_kerpad :: Cint

option only for exp(sqrt()).
0: don't pad kernel to 4n,
1: do

    upsampfac :: Cdouble

upsampling ratio sigma: 2.0 std, 1.25 small FFT, 0.0 auto

    spread_thread :: Cint

(vectorized ntr>1 only):    0: auto, 1: seq multithreaded,
                            2: parallel single-thread spread

    maxbatchsize :: Cint

option for vectorized ntr>1 only:
max transform batch, 0 auto

    spread_nthr_atomic :: Cint

if >=0, threads above which spreader OMP critical goes atomic

    spread_max_sp_size :: Cint

if >0, overrides spreader (dir=1) max subproblem size

"""
mutable struct nufft_opts    
    modeord             :: Cint
    chkbnds             :: Cint              
    # 
    debug               :: Cint                
    spread_debug        :: Cint         
    showwarn            :: Cint
    # 
    nthreads            :: Cint
    fftw                :: Cint                 
    spread_sort         :: Cint          
    spread_kerevalmeth  :: Cint   
    spread_kerpad       :: Cint        
    upsampfac           :: Cdouble         
    spread_thread       :: Cint
    maxbatchsize        :: Cint
    spread_nthr_atomic  :: Cint
    spread_max_sp_size  :: Cint
end

const nufft_c_opts = nufft_opts # backward compability

"""
    finufft_default_opts()

Return a [`nufft_opts`](@ref) struct with the default FINUFFT settings.\\
See: <https://finufft.readthedocs.io/en/latest/usage.html#options>
"""
function finufft_default_opts()
    opts = nufft_opts(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    ccall( (:finufft_default_opts, libfinufft),
           Nothing,
           (Ref{nufft_opts},),
           opts
           )
    # default to number of julia threads
    opts.nthreads = Threads.nthreads()
    return opts
end

### Error handling
const WARN_EPS_TOO_SMALL            = 1
const ERR_MAXNALLOC                 = 2
const ERR_SPREAD_BOX_SMALL          = 3
const ERR_SPREAD_PTS_OUT_RANGE      = 4
const ERR_SPREAD_ALLOC              = 5
const ERR_SPREAD_DIR                = 6
const ERR_UPSAMPFAC_TOO_SMALL       = 7
const HORNER_WRONG_BETA             = 8
const ERR_NDATA_NOTVALID            = 9
const ERR_TYPE_NOTVALID             = 10
# some generic internal allocation failure...
const ERR_ALLOC                     = 11
const ERR_DIM_NOTVALID              = 12
const ERR_SPREAD_THREAD_NOTVALID    = 13

struct FINUFFTError <: Exception
    errno::Cint
    msg::String
end
Base.showerror(io::IO, e::FINUFFTError) = print(io, "FINUFFT Error ($(e.errno)): ", e.msg)

function check_ret(ret)
    # Check return value and output error messages
    if ret==0
        return
    elseif ret==WARN_EPS_TOO_SMALL
        @warn "requested tolerance epsilon too small to achieve"
        return
    elseif ret==ERR_MAXNALLOC
        msg = "attemped to allocate internal array larger than MAX_NF (defined in defs.h)"
    elseif ret==ERR_SPREAD_BOX_SMALL
        msg = "spreader: fine grid too small compared to spread (kernel) width"
    elseif ret==ERR_SPREAD_PTS_OUT_RANGE
        msg = "spreader: if chkbnds=1, a nonuniform point coordinate is out of input range [-3pi,3pi]^d"
    elseif ret==ERR_SPREAD_ALLOC
        msg = "spreader: array allocation error"
    elseif ret==ERR_SPREAD_DIR
        msg = "spreader: illegal direction (should be 1 or 2)"
    elseif ret==ERR_UPSAMPFAC_TOO_SMALL
        msg = "upsampfac too small (should be >1.0)"
    elseif ret==HORNER_WRONG_BETA
        msg = "upsampfac not a value with known Horner poly eval rule (currently 2.0 or 1.25 only)"
    elseif ret==ERR_NDATA_NOTVALID
        msg = "ntrans not valid in many (vectorized) or guru interface (should be >= 1)"
    elseif ret==ERR_TYPE_NOTVALID
        msg = "transform type invalid"
    elseif ret==ERR_ALLOC
        msg = "general allocation failure"
    elseif ret==ERR_DIM_NOTVALID
        msg = "dimension invalid"
    elseif ret==ERR_SPREAD_THREAD_NOTVALID
        msg = "spread_thread option invalid"
    else
        msg = "unknown error"
    end
    throw(FINUFFTError(ret, msg))
end

### Simple Interfaces (allocate output)

## Type-1

"""
    nufft1d1(xj      :: StridedArray{Float64}, 
             cj      :: StridedArray{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             ms      :: Integer
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-1 1D complex nonuniform FFT. 
"""
function nufft1d1(xj::StridedArray{T},
                  cj::StridedArray{Complex{T}},
                  iflag::Integer,
                  eps::T,
                  ms::Integer,
                  opts::nufft_opts=finufft_default_opts()) where T <: Union{Float32,Float64}
    fk = Array{Complex{T}}(undef, ms)
    nufft1d1!(xj, cj, iflag, eps, fk, opts)
    return fk
end

"""
    nufft2d1(xj      :: StridedArray{Float64}, 
             yj      :: StridedArray{Float64}, 
             cj      :: StridedArray{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             ms      :: Integer,
             mt      :: Integer,
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-1 2D complex nonuniform FFT.
"""
function nufft2d1(xj      :: StridedArray{T}, 
                  yj      :: StridedArray{T}, 
                  cj      :: StridedArray{Complex{T}}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  ms      :: Integer,
                  mt      :: Integer,                   
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    fk = Array{Complex{T}}(undef, ms, mt)
    nufft2d1!(xj, yj, cj, iflag, eps, fk, opts)
    return fk
end

"""
    nufft3d1(xj      :: StridedArray{Float64}, 
             yj      :: StridedArray{Float64}, 
             zj      :: StridedArray{Float64}, 
             cj      :: StridedArray{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             ms      :: Integer,
             mt      :: Integer,
             mu      :: Integer,
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-1 3D complex nonuniform FFT.
"""
function nufft3d1(xj      :: StridedArray{T}, 
                  yj      :: StridedArray{T},
                  zj      :: StridedArray{T},                   
                  cj      :: StridedArray{Complex{T}}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  ms      :: Integer,
                  mt      :: Integer,
                  mu      :: Integer,                                     
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    fk = Array{Complex{T}}(undef, ms, mt, mu)
    nufft3d1!(xj, yj, zj, cj, iflag, eps, fk, opts)
    return fk
end


## Type-2

"""
    nufft1d2(xj      :: StridedArray{Float64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             fk      :: StridedArray{ComplexF64} 
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-2 1D complex nonuniform FFT. 
"""
function nufft1d2(xj      :: StridedArray{T},                    
                  iflag   :: Integer, 
                  eps     :: T,
                  fk      :: StridedArray{Complex{T}},
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    cj = Array{Complex{T}}(undef, nj)
    nufft1d2!(xj, cj, iflag, eps, fk, opts)
    return cj
end

"""
    nufft2d2(xj      :: StridedArray{Float64}, 
             yj      :: StridedArray{Float64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             fk      :: StridedArray{ComplexF64} 
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-2 2D complex nonuniform FFT. 
"""
function nufft2d2(xj      :: StridedArray{T}, 
                  yj      :: StridedArray{T}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  fk      :: StridedArray{Complex{T}},
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    cj = Array{Complex{T}}(undef, nj)
    nufft2d2!(xj, yj, cj, iflag, eps, fk, opts)
    return cj
end

"""
    nufft3d2(xj      :: StridedArray{Float64}, 
             yj      :: StridedArray{Float64}, 
             zj      :: StridedArray{Float64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             fk      :: StridedArray{ComplexF64} 
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-2 3D complex nonuniform FFT. 
"""
function nufft3d2(xj      :: StridedArray{T}, 
                  yj      :: StridedArray{T},
                  zj      :: StridedArray{T}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  fk      :: StridedArray{Complex{T}},
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    cj = Array{Complex{T}}(undef, nj)
    nufft3d2!(xj, yj, zj, cj, iflag, eps, fk, opts)
    return cj
end


## Type-3

"""
    nufft1d3(xj      :: StridedArray{Float64}, 
             cj      :: StridedArray{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             sk      :: StridedArray{Float64},
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-3 1D complex nonuniform FFT.
"""
function nufft1d3(xj      :: StridedArray{T}, 
                  cj      :: StridedArray{Complex{T}}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  sk      :: StridedArray{T},
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(cj)==nj        
    nk = length(sk)
    fk = Array{Complex{T}}(undef, nk)
    nufft1d3!(xj, cj, iflag, eps, sk, fk, opts)
    return fk
end

"""
    nufft2d3(xj      :: StridedArray{Float64}, 
             yj      :: StridedArray{Float64},
             cj      :: StridedArray{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             sk      :: StridedArray{Float64},
             tk      :: StridedArray{Float64}
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-3 2D complex nonuniform FFT.
"""
function nufft2d3(xj      :: StridedArray{T},
                  yj      :: StridedArray{T}, 
                  cj      :: StridedArray{Complex{T}}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  sk      :: StridedArray{T},
                  tk      :: StridedArray{T},                  
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(cj)==nj        
    nk = length(sk)
    fk = Array{Complex{T}}(undef, nk)
    nufft2d3!(xj, yj, cj, iflag, eps, sk, tk, fk, opts)
    return fk
end

"""
    nufft3d3(xj      :: StridedArray{Float64}, 
             yj      :: StridedArray{Float64},
             zj      :: StridedArray{Float64},
             cj      :: StridedArray{ComplexF64}, 
             iflag   :: Integer, 
             eps     :: Float64,
             sk      :: StridedArray{Float64},
             tk      :: StridedArray{Float64}
             uk      :: StridedArray{Float64}
             [, opts :: nufft_opts]
            ) -> Array{ComplexF64}

Compute type-3 3D complex nonuniform FFT.
"""
function nufft3d3(xj      :: StridedArray{T},
                  yj      :: StridedArray{T},
                  zj      :: StridedArray{T},                   
                  cj      :: StridedArray{Complex{T}}, 
                  iflag   :: Integer, 
                  eps     :: T,
                  sk      :: StridedArray{T},
                  tk      :: StridedArray{T},
                  uk      :: StridedArray{T},                  
                  opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(cj)==nj        
    nk = length(sk)
    fk = Array{Complex{T}}(undef, nk)
    nufft3d3!(xj, yj, zj, cj, iflag, eps, sk, tk, uk, fk, opts)
    return fk
end


### Direct interfaces (No allocation)

## 1D

"""
    nufft1d1!(xj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: StridedArray{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-1 1D complex nonuniform FFT. Output stored in fk.
"""
function nufft1d1!(xj      :: StridedArray{T}, 
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj) 
    @assert length(cj) == nj        
    ms = length(fk)

    p = finufft_makeplan(1, 1, (ms, 1, 1), iflag, 1, eps, opts)
    finufft_setpts(p, xj)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end



"""
    nufft1d2!(xj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: StridedArray{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-2 1D complex nonuniform FFT. Output stored in cj.
"""
function nufft1d2!(xj      :: StridedArray{T}, 
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(cj)==nj        
    ms = length(fk)    
    
    p = finufft_makeplan(2, 1, (ms, 1, 1), iflag, 1, eps, opts)
    finufft_setpts(p, xj)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)  
end

"""
    nufft1d3!(xj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              sk      :: StridedArray{Float64},
              fk      :: StridedArray{ComplexF64},
              [, opts :: nufft_opts]
             )

Compute type-3 1D complex nonuniform FFT. Output stored in fk.
"""
function nufft1d3!(xj      :: StridedArray{T}, 
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   sk      :: StridedArray{T},
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(cj)==nj        
    nk = length(sk)
    @assert length(fk)==nk
    ms = length(sk)
    
    p = finufft_makeplan(3, 1, (0, 0, 0), iflag, 1, eps, opts)
    finufft_setpts(p, xj, T[], T[], sk)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end


## 2D

"""
    nufft2d1!(xj      :: StridedArray{Float64}, 
              yj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: StridedArray{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-1 2D complex nonuniform FFT. Output stored in fk.
"""
function nufft2d1!(xj      :: StridedArray{T}, 
                   yj      :: StridedArray{T}, 
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(yj)==nj
    @assert length(cj)==nj    
    ms, mt = size(fk)    
   
    p = finufft_makeplan(1, 2, (ms, mt, 1), iflag, 1, eps, opts)
    finufft_setpts(p, xj, yj)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end


"""
    nufft2d2!(xj      :: StridedArray{Float64}, 
              yj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: StridedArray{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-2 2D complex nonuniform FFT. Output stored in cj.
"""
function nufft2d2!(xj      :: StridedArray{T}, 
                   yj      :: StridedArray{T}, 
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(yj)==nj
    @assert length(cj)==nj    
    ms, mt = size(fk)
    
    p = finufft_makeplan(2, 2, (ms, mt, 1), iflag, 1, eps, opts)
    finufft_setpts(p, xj, yj)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end

"""
    nufft2d3!(xj      :: StridedArray{Float64}, 
              yj      :: StridedArray{Float64},
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              sk      :: StridedArray{Float64},
              tk      :: StridedArray{Float64},
              fk      :: StridedArray{ComplexF64}
              [, opts :: nufft_opts]
             )

Compute type-3 2D complex nonuniform FFT. Output stored in fk.
"""
function nufft2d3!(xj      :: StridedArray{T}, 
                   yj      :: StridedArray{T},
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   sk      :: StridedArray{T},
                   tk      :: StridedArray{T},
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(yj)==nj
    @assert length(cj)==nj
    nk = length(sk)
    @assert length(tk)==nk
    @assert length(fk)==nk
    
    p = finufft_makeplan(3, 2, (0, 0, 0), iflag, 1, eps, opts)
    finufft_setpts(p, xj, yj, T[], sk, tk)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end

## 3D

"""
    nufft3d1!(xj      :: StridedArray{Float64}, 
              yj      :: StridedArray{Float64}, 
              zj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: StridedArray{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-1 3D complex nonuniform FFT. Output stored in fk.
"""
function nufft3d1!(xj      :: StridedArray{T}, 
                   yj      :: StridedArray{T}, 
                   zj      :: StridedArray{T}, 
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj    
    ms, mt, mu = size(fk)    
    
    p = finufft_makeplan(1, 3, (ms, mt, mu), iflag, 1, eps, opts)
    finufft_setpts(p, xj, yj, zj)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)  
end

"""
    nufft3d2!(xj      :: StridedArray{Float64}, 
              yj      :: StridedArray{Float64}, 
              zj      :: StridedArray{Float64}, 
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              fk      :: StridedArray{ComplexF64} 
              [, opts :: nufft_opts]
            )

Compute type-2 3D complex nonuniform FFT. Output stored in cj.
"""
function nufft3d2!(xj      :: StridedArray{T}, 
                   yj      :: StridedArray{T},
                   zj      :: StridedArray{T},                    
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj    
    ms, mt, mu = size(fk)    
    
    p = finufft_makeplan(2, 3, (ms, mt, mu), iflag, 1, eps, opts)
    finufft_setpts(p, xj, yj, zj)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end

"""
    nufft3d3!(xj      :: StridedArray{Float64}, 
              yj      :: StridedArray{Float64},
              zj      :: StridedArray{Float64},
              cj      :: StridedArray{ComplexF64}, 
              iflag   :: Integer, 
              eps     :: Float64,
              sk      :: StridedArray{Float64},
              tk      :: StridedArray{Float64},
              uk      :: StridedArray{Float64},
              fk      :: StridedArray{ComplexF64}
              [, opts :: nufft_opts]
             )

Compute type-3 3D complex nonuniform FFT. Output stored in fk.
"""
function nufft3d3!(xj      :: StridedArray{T}, 
                   yj      :: StridedArray{T},
                   zj      :: StridedArray{T},                   
                   cj      :: StridedArray{Complex{T}}, 
                   iflag   :: Integer, 
                   eps     :: T,
                   sk      :: StridedArray{T},
                   tk      :: StridedArray{T},
                   uk      :: StridedArray{T},
                   fk      :: StridedArray{Complex{T}},
                   opts    :: nufft_opts = finufft_default_opts()) where T <: Union{Float32,Float64}
    nj = length(xj)
    @assert length(yj)==nj
    @assert length(zj)==nj    
    @assert length(cj)==nj
    nk = length(sk)
    @assert length(tk)==nk
    @assert length(uk)==nk    
    @assert length(fk)==nk
    
    p = finufft_makeplan(3, 3, (0, 0, 0), iflag, 1, eps, opts)
    finufft_setpts(p, xj, yj, zj, sk, tk, uk)
    finufft_exec(p, cj, fk)
    finufft_destroy(p)
end


function __init__()
    # generate plan once per precision to ensure thread-safety
    finufft_destroy(finufft_makeplan(1,1,[100;1;1],1,1,1f-4))
    finufft_destroy(finufft_makeplan(1,1,[100;1;1],1,1,1e-4))
end

include("guru.jl")



# keep nufftf calls for compability
const nufftf1d1 = nufft1d1
const nufftf1d2 = nufft1d2
const nufftf1d3 = nufft1d3
const nufftf2d1 = nufft2d1
const nufftf2d2 = nufft2d2
const nufftf2d3 = nufft2d3
const nufftf3d1 = nufft3d1
const nufftf3d2 = nufft3d2
const nufftf3d3 = nufft3d3

const nufftf1d1! = nufft1d1!
const nufftf1d2! = nufft1d2!
const nufftf1d3! = nufft1d3!
const nufftf2d1! = nufft2d1!
const nufftf2d2! = nufft2d2!
const nufftf2d3! = nufft2d3!
const nufftf3d1! = nufft3d1!
const nufftf3d2! = nufft3d2!
const nufftf3d3! = nufft3d3!

end # module
