import cemalloc
import numpy as np

cemalloc.SetCxlMemory()
arr = np.zeros(1024)       # arr will be allocated on CE_CXL_NODE

cemalloc.SetHostMemory()
arr2 = np.zeros(1024) 