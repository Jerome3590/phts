FROM public.ecr.aws/lambda/python:3.9

# Install system dependencies for model libraries
RUN yum install -y gcc g++ gcc-c++ make && \
    yum clean all && \
    rm -rf /var/cache/yum

# Copy requirements and install Python dependencies
COPY requirements.txt ${LAMBDA_TASK_ROOT}
RUN pip install --no-cache-dir -r requirements.txt

# Copy function code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY utils/ ${LAMBDA_TASK_ROOT}/utils/

# Create models cache directory
RUN mkdir -p /tmp/models && chmod 777 /tmp/models

# Set handler
CMD [ "lambda_function.handler" ]

