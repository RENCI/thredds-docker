# Dockerfile for TDS
FROM unidata/tomcat-docker:8.5-jdk11-openjdk

MAINTAINER Unidata

# confirm we are root to create the installation
USER root

# note that CATALINA_HOME is inherited from the root container image. we will continue to use
# that until we switch to the new catalina directory structure for the non-root user below.

# install basic image tools and updates
RUN apt-get update && \
    apt-get install -y unzip vim build-essential m4 \
    libpthread-stubs0-dev libcurl4-openssl-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# create environmant variables
ENV LD_LIBRARY_PATH /usr/local/lib:${LD_LIBRARY_PATH}
ENV HDF5_VERSION 1.10.5
ENV ZLIB_VERSION 1.2.9
ENV NETCDF_VERSION 4.7.2
ENV ZDIR /usr/local
ENV H5DIR /usr/local
ENV PDIR /usr
ENV HDF5_VER hdf5-${HDF5_VERSION}
ENV HDF5_FILE ${HDF5_VER}.tar.gz

# install zlib dependency
RUN curl https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz | tar xz && \
    cd zlib-${ZLIB_VERSION} && \
    ./configure --prefix=/usr/local && \
    make && make install && \
    cd .. && rm -rf zlib-${ZLIB_VERSION}

# install hdf5 dependency
RUN curl https://support.hdfgroup.org/ftp/HDF5/releases/${HDF5_VER%.*}/${HDF5_VER}/src/${HDF5_FILE} | tar xz && \
    cd hdf5-${HDF5_VERSION} && \
    ./configure --with-zlib=${ZDIR} --prefix=${H5DIR} --enable-threadsafe --with-pthread=${PDIR} --enable-unsupported --prefix=/usr/local && \
    make && make check && make install && make check-install && ldconfig && \
    cd .. && rm -rf hdf5-${HDF5_VERSION}

# install netCDF4-c dependency
RUN export CPPFLAGS=-I/usr/local/include \
    LDFLAGS=-L/usr/local/lib && \
    curl ftp://ftp.unidata.ucar.edu/pub/netcdf/netcdf-c-${NETCDF_VERSION}.tar.gz | tar xz && \
    cd netcdf-c-${NETCDF_VERSION} && \
    ./configure --disable-dap-remote-tests --prefix=/usr/local && \
    make check && make install && ldconfig && \
    cd .. && rm -rf netcdf-c-${NETCDF_VERSION}

# declare the THREDDS content directory as the non-root user.
ENV TDS_CONTENT_ROOT_PATH /home/nru/tomcat/content

# The amount of Xmx and Xms memory Java args to allocate to THREDDS
ENV THREDDS_XMX_SIZE 4G
ENV THREDDS_XMS_SIZE 4G

# pull in the THREDDS website deploy
ENV THREDDS_WAR_URL=https://downloads.unidata.ucar.edu/tds/5.3/thredds%2523%25235.3.war
RUN curl -fSL "${THREDDS_WAR_URL}" -o thredds.war && \
    unzip thredds.war -d ${CATALINA_HOME}/webapps/thredds/ && \
    rm -f thredds.war

# create the THREDDS config content directory
RUN mkdir -p ${CATALINA_HOME}/content/thredds

# copy in the RENCI THREDDS users and configs
COPY ./files/threddsConfig.xml ${CATALINA_HOME}/content/thredds/threddsConfig.xml
COPY ./files/tomcat-users.xml ${CATALINA_HOME}/conf/tomcat-users.xml

# copy in the tomcat java options
COPY ./files/setenv.sh ${CATALINA_HOME}/bin/setenv.sh
COPY ./files/javaopts.sh ${CATALINA_HOME}/bin/javaopts.sh
RUN chmod 755 ${CATALINA_HOME}/bin/*.sh

# Create the .systemPrefs directory
RUN mkdir -p ${CATALINA_HOME}/javaUtilPrefs/.systemPrefs

# add RENCI catalog configuration files
COPY ./files/catalog.xml ${CATALINA_HOME}/content/thredds/catalog.xml
COPY ./files/asgs2021.xml ${CATALINA_HOME}/content/thredds/asgs2021.xml
COPY ./files/asgs2022.xml ${CATALINA_HOME}/content/thredds/asgs2022.xml

# add the renci website branding
COPY ./files/renci-logo.png ${CATALINA_HOME}/webapps/thredds/renci-logo.png
COPY ./files/tds.css ${CATALINA_HOME}/webapps/thredds/tds.css

# create the non-root user and move the entire site config there
RUN useradd -ms /bin/bash nru &&  \
    mv /usr/local/tomcat /home/nru/ && \
    rm -rf /usr/local/tomcat

# make sure the non-root user is the owner of everything
RUN chown -R nru:nru /home/nru/

# set the working directory to the non-root user
WORKDIR /home/nru

# reset the home directory for the tomcat startup
ENV CATALINA_HOME /home/nru/tomcat

# Expose ports
EXPOSE 8080 8443

# switch to the non-root user
USER nru

# start the site, inherited from parent container
ENTRYPOINT ["/entrypoint.sh", "/home/nru/tomcat/bin/catalina.sh", "run"]
