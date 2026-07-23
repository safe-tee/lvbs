#!/bin/bash

autoreconf -vif .. \
	&& \
	../configure \
		--prefix=/usr
